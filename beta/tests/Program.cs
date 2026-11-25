using System.Threading.Channels;
using AirPodsBuddy.Beta;

int checks = 0;
void Check(bool value, string label) { if (!value) throw new Exception("FAIL " + label); checks++; }
byte[] Hex(string value) => Convert.FromHexString(value);
Check(Protocol.Handshake.SequenceEqual(Hex("00000400010002000000000000000000")), "handshake exact");
Check(Protocol.Subscribe.SequenceEqual(Hex("040004000F00FFFFFEFF")), "subscribe exact");
Check(Protocol.H2Features.SequenceEqual(Hex("040004004D00FF00000000000000")), "h2 opt-in exact");
foreach (var mode in Enum.GetValues<NoiseMode>())
{
    var bytes = Protocol.SetNoise(mode);
    Check(bytes.Length == 11 && bytes[7] == (byte)mode, "11-byte mode command " + mode);
    Check(Protocol.Decode(bytes).Single() == new Noise(mode), "mode readback " + mode);
    for (int cut = 0; cut < bytes.Length; cut++) Check(Protocol.Decode(bytes.AsSpan(0, cut)).Count == 0, "truncated mode");
}
try { Protocol.SetNoise((NoiseMode)255); Check(false, "invalid mode rejected"); }
catch (ArgumentOutOfRangeException) { Check(true, "invalid mode rejected"); }
for (byte primary = 0; primary < 3; primary++)
for (byte secondary = 0; secondary < 3; secondary++)
{
    byte[] packet = [4, 0, 4, 0, 6, 0, primary, secondary];
    Check(Protocol.Decode(packet).Single() == new Ears((EarState)primary, (EarState)secondary), "primary secondary mapping");
}
Check(Protocol.Decode(Hex("040004000600FF00")).Count == 0, "unknown ear is not in-ear");
Check(Protocol.Decode(Hex("0400040009000D05000000")).Count == 0, "unknown mode ignored");
Check(Protocol.Decode(Hex("0400040009000D03010000")).Count == 0, "invalid mode reserved bytes");
Check(Protocol.Decode(Hex("0400040009000E03000000")).Count == 0, "other property ignored");
foreach (int level in new[] { 0, 25, 50, 75, 100 })
{
    var packet = Protocol.SetAdaptiveLevel(level);
    Check(packet.Length == 11 && packet[6] == 0x2e && packet[7] == level, "adaptive level command");
    Check(Protocol.Decode(packet).Single() == new AdaptiveNoise((byte)level), "adaptive level report");
}
Check(Protocol.Decode(Hex("0400040009002E65000000")).Count == 0, "unknown adaptive level rejected");
Check(Protocol.Decode(Hex("0400040009002E32010000")).Count == 0, "adaptive reserved bytes rejected");
try { Protocol.SetAdaptiveLevel(-1); Check(false,"invalid adaptive low"); } catch (ArgumentOutOfRangeException) { Check(true,"invalid adaptive low"); }
try { Protocol.SetAdaptiveLevel(101); Check(false,"invalid adaptive high"); } catch (ArgumentOutOfRangeException) { Check(true,"invalid adaptive high"); }

Check(Protocol.Decode(Hex("040004001D000400040006000000")).Count == 0, "metadata never rescanned as ear report");
Check(Protocol.Decode(Hex("04000400060000010400040009000D02000000")).Count == 2, "coalesced known records");
Check(Protocol.Decode(Hex("0400040004000102016402010400040006000000")).Single() is Ears, "skip bounded battery");
Check(Protocol.Decode(Hex("040004000400FF0400040006000000")).Count == 0, "invalid battery cannot spoof ears");
var random = new Random(21);
for (int i = 0; i < 3000; i++) { byte[] data = new byte[random.Next(0, 512)]; random.NextBytes(data); Check(Protocol.Decode(data).Count == 0, "random noise ignored"); }
Check(Models.Resolve(Models.Choices[0], "Alice AirPods Pro 3") == "AirPods Pro 3", "name inferred pro3");
Check(Models.Resolve(Models.Choices[0], "MagicAAP") == "其他 / 未知", "no fake automatic identity");
Check(Models.Resolve("AirPods Pro 2", "AirPods Pro 3") == "AirPods Pro 2", "manual override");
Check(!Models.SupportsNoise("其他 / 未知"), "unknown not granted controls");
Check(!Models.SupportsAdaptive("AirPods Pro") && Models.SupportsAdaptive("AirPods Pro 3"), "model capability gate");

var fake = new FakeChannel();
await using (var session = new Session(fake))
{
    int reports = 0;
    session.Observed += _ => Interlocked.Increment(ref reports);
    await session.StartAsync(false, TimeSpan.FromSeconds(1));
    Check(fake.Writes.Count == 2, "h2 disabled by default");
    Check(fake.Writes[0].SequenceEqual(Protocol.Handshake) && fake.Writes[1].SequenceEqual(Protocol.Subscribe), "initialization order");
    fake.Push(Protocol.SetNoise(NoiseMode.Anc));
    await Until(() => Volatile.Read(ref reports) > 0);
    // The prior matching report must NOT acknowledge this command.
    var request = session.ChangeNoiseAsync(NoiseMode.Anc, TimeSpan.FromSeconds(1));
    await Task.Delay(25);
    Check(!request.IsCompleted, "old readback rejected");
    fake.Push(Protocol.SetNoise(NoiseMode.Anc));
    Check(await request == NoiseMode.Anc, "fresh matching state returned");
    var mismatch = session.ChangeNoiseAsync(NoiseMode.Transparency, TimeSpan.FromSeconds(1));
    await Task.Delay(10); fake.Push(Protocol.SetNoise(NoiseMode.Anc));
    Check(await mismatch != NoiseMode.Transparency, "mismatch not success");
    await session.DisposeAsync();
    Check(!session.IsOpen && fake.Disposed, "disconnect disposes handle");
}

fake = new FakeChannel();
await using (var session = new Session(fake))
{
    await session.StartAsync(true, TimeSpan.FromSeconds(1));
    Check(fake.Writes.Count == 3 && fake.Writes[1].SequenceEqual(Protocol.H2Features), "h2 explicit opt-in");
    try { await session.ChangeNoiseAsync(NoiseMode.Anc, TimeSpan.FromMilliseconds(35)); Check(false, "timeout"); }
    catch (OperationCanceledException) { Check(true, "timeout"); }
    Check(!session.IsOpen && fake.Disposed, "timeout closes channel");
    try { await session.ChangeNoiseAsync(NoiseMode.Anc, TimeSpan.FromSeconds(1)); Check(false, "no reuse after timeout"); }
    catch (OperationCanceledException) { Check(true, "no reuse after timeout"); }
}

fake = new FakeChannel { FailWrites = true };
await using (var session = new Session(fake))
{
    try { await session.StartAsync(false, TimeSpan.FromSeconds(1)); Check(false, "handshake failure"); }
    catch (IOException) { Check(true, "handshake failure"); }
    Check(fake.Disposed && !session.IsOpen, "failed startup cleans handle");
}

fake = new FakeChannel();
await using (var session = new Session(fake))
{
    await session.StartAsync(false, TimeSpan.FromSeconds(1));
    var request = session.ChangeNoiseAsync(NoiseMode.Anc, TimeSpan.FromSeconds(1));
    var queued = session.ChangeNoiseAsync(NoiseMode.Transparency, TimeSpan.FromSeconds(1));
    await Task.Delay(15);
    Check(fake.Writes.Count == 3, "command serialization");
    await session.DisposeAsync();
    try { await request; Check(false, "cancel request"); } catch (OperationCanceledException) { Check(true, "cancel request"); }
    try { await queued; Check(false, "cancel queue"); } catch (OperationCanceledException) { Check(true, "cancel queue"); }
    Check(fake.Disposed, "cancel queue cleans handle");
}

fake = new FakeChannel();
await using (var session = new Session(fake))
{
    await session.StartAsync(false, TimeSpan.FromSeconds(1));
    fake.Push([]);
    await Until(() => !session.IsOpen);
    Check(fake.Disposed, "unsolicited EOF cleans handle");
}

fake = new FakeChannel();
await using (var session = new Session(fake))
{
    await session.StartAsync(true, TimeSpan.FromSeconds(1));
    try { await session.ChangeAdaptiveLevelAsync(50, TimeSpan.FromSeconds(1)); Check(false, "adaptive requires observed mode"); }
    catch (InvalidOperationException) { Check(session.IsOpen && fake.Writes.Count == 3, "adaptive requires observed mode; no write"); }
    int seen = 0;
    session.Observed += _ => Interlocked.Increment(ref seen);
    fake.Push(Protocol.SetNoise(NoiseMode.Adaptive)); fake.Push(Protocol.SetAdaptiveLevel(50));
    await Until(() => Volatile.Read(ref seen) >= 2);
    var request = session.ChangeAdaptiveLevelAsync(50, TimeSpan.FromSeconds(1));
    await Task.Delay(25);
    Check(!request.IsCompleted, "old adaptive readback rejected");
    fake.Push(Protocol.SetNoise(NoiseMode.Adaptive));
    await Task.Delay(15);
    Check(!request.IsCompleted, "noise report cannot satisfy adaptive request");
    fake.Push(Protocol.SetAdaptiveLevel(50));
    Check(await request == 50, "fresh adaptive readback matches");
    var mismatch = session.ChangeAdaptiveLevelAsync(75, TimeSpan.FromSeconds(1));
    await Task.Delay(15); fake.Push(Protocol.SetAdaptiveLevel(25));
    Check(await mismatch == 25, "adaptive mismatch returned as evidence");
    try { await session.ChangeAdaptiveLevelAsync(75, TimeSpan.FromMilliseconds(50)); Check(false, "adaptive timeout"); }
    catch (OperationCanceledException) { Check(!session.IsOpen && fake.Disposed, "adaptive timeout closes session"); }
}

Console.WriteLine($"BETA_PASS assertions={checks} hardware=false");

static async Task Until(Func<bool> predicate)
{
    using var timeout = new CancellationTokenSource(2000);
    while (!predicate()) await Task.Delay(5, timeout.Token);
}

sealed class FakeChannel : IChannel
{
    readonly Channel<byte[]> incoming = Channel.CreateUnbounded<byte[]>();
    public readonly List<byte[]> Writes = new();
    public bool Disposed;
    public bool FailWrites;
    public void Push(byte[] packet) => incoming.Writer.TryWrite(packet);
    public Task WriteAsync(byte[] packet, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (FailWrites) throw new IOException("Injected write failure");
        lock (Writes) Writes.Add(packet.ToArray());
        return Task.CompletedTask;
    }
    public async Task<byte[]> ReadAsync(CancellationToken token) => await incoming.Reader.ReadAsync(token);
    public ValueTask DisposeAsync() { Disposed = true; return ValueTask.CompletedTask; }
}
