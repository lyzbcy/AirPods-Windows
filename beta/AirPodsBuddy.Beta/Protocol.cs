namespace AirPodsBuddy.Beta;

public enum NoiseMode : byte { Off = 1, Anc = 2, Transparency = 3, Adaptive = 4 }
public enum EarState : byte { InEar = 0, Out = 1, InCase = 2 }
public abstract record Report;
// AAP reports primary/secondary, NOT physical left/right.
public sealed record Ears(EarState Primary, EarState Secondary) : Report;
public sealed record Noise(NoiseMode Mode) : Report;
public sealed record AdaptiveNoise(byte Level) : Report;

public static class Protocol
{
    public static byte[] Handshake => Convert.FromHexString("00000400010002000000000000000000");
    public static byte[] Subscribe => Convert.FromHexString("040004000F00FFFFFEFF");
    // This capability packet is only sent when the user explicitly enables H2 experimentation.
    public static byte[] H2Features => Convert.FromHexString("040004004D00FF00000000000000");
    public static byte[] SetNoise(NoiseMode mode)
    {
        if (!Enum.IsDefined(mode)) throw new ArgumentOutOfRangeException(nameof(mode));
        return [4, 0, 4, 0, 9, 0, 13, (byte)mode, 0, 0, 0];
    }
    // Publicly documented adaptive noise level, effective in Adaptive mode.
    public static byte[] SetAdaptiveLevel(int level)
    {
        if (level is < 0 or > 100) throw new ArgumentOutOfRangeException(nameof(level));
        return [4, 0, 4, 0, 9, 0, 0x2e, (byte)level, 0, 0, 0];
    }
    // One driver read is treated as a packet batch, not an unbounded byte stream.
    // Unknown/truncated packets are ignored: never scan their payload for fake status headers.
    public static IReadOnlyList<Report> Decode(ReadOnlySpan<byte> bytes)
    {
        var result = new List<Report>();
        while (bytes.Length >= 6 && bytes[0] == 4 && bytes[1] == 0 && bytes[2] == 4 && bytes[3] == 0 && bytes[5] == 0)
        {
            int length;
            if (bytes[4] == 6)
            {
                length = 8;
                if (bytes.Length < length) break;
                if (bytes[6] <= 2 && bytes[7] <= 2) result.Add(new Ears((EarState)bytes[6], (EarState)bytes[7]));
            }
            else if (bytes[4] == 9)
            {
                length = 11;
                if (bytes.Length < length) break;
                if (bytes[6] == 13 && bytes[7] is >= 1 and <= 4 && bytes[8] == 0 && bytes[9] == 0 && bytes[10] == 0)
                    result.Add(new Noise((NoiseMode)bytes[7]));
                else if (bytes[6] == 0x2e && bytes[7] <= 100 && bytes[8] == 0 && bytes[9] == 0 && bytes[10] == 0)
                    result.Add(new AdaptiveNoise(bytes[7]));
            }
            else if (bytes[4] == 4)
            {
                if (bytes.Length < 7 || bytes[6] > 3) break;
                length = 7 + 5 * bytes[6];
                if (bytes.Length < length) break;
                // Skip battery packets without interpreting private metadata or device identity.
            }
            else break;
            bytes = bytes[length..];
        }
        return result;
    }
}

public static class Models
{
    public static readonly string[] Choices = ["自动（名称推测）", "AirPods Pro", "AirPods Pro 2", "AirPods Pro 3", "AirPods 4 ANC", "AirPods Max", "其他 / 未知"];
    public static string Resolve(string choice, string deviceName)
    {
        if (choice != Choices[0]) return choice;
        string name = deviceName.ToLowerInvariant();
        if (name.Contains("airpods pro 3") || name.Contains("airpods pro3")) return Choices[3];
        if (name.Contains("airpods pro 2") || name.Contains("airpods pro2")) return Choices[2];
        if (name.Contains("airpods pro")) return Choices[1];
        if (name.Contains("airpods 4") && name.Contains("anc")) return Choices[4];
        if (name.Contains("airpods max")) return Choices[5];
        return Choices[6];
    }
    public static bool SupportsNoise(string model) => Choices.Skip(1).Take(5).Contains(model);
    public static bool SupportsAdaptive(string model) => model is "AirPods Pro 2" or "AirPods Pro 3" or "AirPods 4 ANC";
}
