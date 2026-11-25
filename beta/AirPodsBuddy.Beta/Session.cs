namespace AirPodsBuddy.Beta;

public interface IChannel : IAsyncDisposable
{
    Task WriteAsync(byte[] packet, CancellationToken token);
    Task<byte[]> ReadAsync(CancellationToken token);
}

public sealed class Session : IAsyncDisposable
{
    readonly IChannel channel;
    readonly CancellationTokenSource lifetime = new();
    readonly SemaphoreSlim commands = new(1, 1);
    readonly object gate = new();
    Task? reader;
    TaskCompletionSource<Report>? pending;
    Type? pendingType;
    NoiseMode? observedMode;
    int closed;
    public bool IsOpen => Volatile.Read(ref closed) == 0 && reader != null && !reader.IsCompleted;
    public event Action<Report>? Observed;
    public event Action<string>? Ended;
    public Session(IChannel channel) => this.channel = channel;

    public async Task StartAsync(bool enableH2, TimeSpan timeout)
    {
        if (reader != null || Volatile.Read(ref closed) != 0) throw new InvalidOperationException("Session already used");
        using var limit = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        limit.CancelAfter(timeout);
        reader = ReceiveAsync();
        try
        {
            await channel.WriteAsync(Protocol.Handshake, limit.Token);
            if (enableH2) await channel.WriteAsync(Protocol.H2Features, limit.Token);
            await channel.WriteAsync(Protocol.Subscribe, limit.Token);
        }
        catch { await DisposeAsync(); throw; }
    }

    async Task ReceiveAsync()
    {
        string reason = "控制通道已关闭";
        try
        {
            while (!lifetime.IsCancellationRequested)
            {
                var packet = await channel.ReadAsync(lifetime.Token);
                if (packet.Length == 0) throw new IOException("End of control channel");
                foreach (var report in Protocol.Decode(packet))
                {
                    lock (gate)
                    {
                        if (report is Noise noise) observedMode = noise.Mode;
                        if (pendingType?.IsInstanceOfType(report) == true) pending?.TrySetResult(report);
                    }
                    Observed?.Invoke(report);
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception e) { reason = $"控制通道中断（{e.GetType().Name}，0x{e.HResult:X8}）"; }
        finally
        {
            Interlocked.Exchange(ref closed, 1);
            lifetime.Cancel();
            lock (gate) pending?.TrySetCanceled();
            // Close the device even on unsolicited EOF/failure, not only when the UI disconnects.
            await channel.DisposeAsync();
            Ended?.Invoke(reason);
        }
    }

    public async Task<NoiseMode> ChangeNoiseAsync(NoiseMode mode, TimeSpan timeout) =>
        (await ChangeAsync<Noise>(Protocol.SetNoise(mode), timeout)).Mode;

    public async Task<byte> ChangeAdaptiveLevelAsync(int level, TimeSpan timeout) =>
        (await ChangeAsync<AdaptiveNoise>(Protocol.SetAdaptiveLevel(level), timeout, adaptiveOnly: true)).Level;

    async Task<T> ChangeAsync<T>(byte[] packet, TimeSpan timeout, bool adaptiveOnly = false) where T : Report
    {
        await commands.WaitAsync(lifetime.Token);
        bool operationStarted = false;
        try
        {
            if (!IsOpen) throw new IOException("Control channel is closed");
            if (adaptiveOnly)
            {
                lock (gate)
                    if (observedMode != NoiseMode.Adaptive)
                        throw new InvalidOperationException("Adaptive mode has not been observed");
            }
            using var limit = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            limit.CancelAfter(timeout);
            operationStarted = true;
            await channel.WriteAsync(packet, limit.Token);
            // Conservative boundary: only observations AFTER completed write count.
            // No protocol transaction ID exists; this is state observation, not an attributed ACK.
            var wait = new TaskCompletionSource<Report>(TaskCreationOptions.RunContinuationsAsynchronously);
            lock (gate) { pending = wait; pendingType = typeof(T); }
            try { return (T)await wait.Task.WaitAsync(limit.Token); }
            finally { lock (gate) { pending = null; pendingType = null; } }
        }
        catch
        {
            // Never reuse a timed-out session for a new command (late replies would be ambiguous).
            if (operationStarted) await DisposeAsync();
            throw;
        }
        finally { commands.Release(); }
    }

    public async ValueTask DisposeAsync()
    {
        Interlocked.Exchange(ref closed, 1);
        lifetime.Cancel();
        lock (gate) pending?.TrySetCanceled();
        await channel.DisposeAsync();
        if (reader != null) await reader;
    }
}
