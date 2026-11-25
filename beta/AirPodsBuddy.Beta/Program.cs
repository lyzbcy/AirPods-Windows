using System.Text.Json;

namespace AirPodsBuddy.Beta;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        // Diagnostics never open a device or change Bluetooth/audio settings.
        if (args.Length == 2 && args[0] == "--probe")
        {
            try
            {
                int count = Driver.Probe().Count;
                File.WriteAllText(args[1], JsonSerializer.Serialize(new { version = "1.10.0-beta.2", interfaces = count, opened = false, settingsChanged = false }));
                return 0;
            }
            catch (Exception e)
            {
                File.WriteAllText(args[1], JsonSerializer.Serialize(new { error = e.GetType().Name, code = e.HResult }));
                return 1;
            }
        }
        ApplicationConfiguration.Initialize();
        using var form = new MainForm();
        if (args.Length == 2 && args[0] == "--smoke-test")
        {
            form.Opacity = 0;
            form.ShowInTaskbar = false;
            form.Shown += async (_, _) =>
            {
                try
                {
                    string receipt = await form.RunSmokeAsync();
                    form.SaveSmokeImage(args[1] + ".png");
                    File.WriteAllText(args[1], receipt);
                }
                finally { form.Close(); }
            };
        }
        Application.Run(form);
        return 0;
    }
}

sealed class MainForm : Form
{
    readonly ComboBox devices = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 490 };
    readonly ComboBox model = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 250 };
    readonly Button scan = new() { Text = "检测控制通道", AutoSize = true };
    readonly Button connect = new() { Text = "打开控制通道", AutoSize = true };
    readonly Button disconnect = new() { Text = "关闭控制通道", AutoSize = true, Enabled = false };
    readonly CheckBox experimental = new() { Text = "启用 H2 实验能力（仅本次连接；自适应仍待真机验证）", AutoSize = true };
    readonly Label channel = new() { Text = "尚未检测。普通蓝牙连接 ≠ AAP 控制通道可用。", AutoSize = true, MaximumSize = new Size(740, 0) };
    readonly Label identity = new() { Text = "型号：未知", AutoSize = true, MaximumSize = new Size(740, 0) };
    readonly Label ears = new() { Text = "入耳状态：未知（等待设备上报）", AutoSize = true };
    readonly Label noise = new() { Text = "降噪模式：未知（等待设备上报）", AutoSize = true };
    readonly TrackBar adaptiveLevel = new() { Minimum = 0, Maximum = 100, Value = 50, TickFrequency = 25, Width = 300, Enabled = false };
    readonly Button applyAdaptive = new() { Text = "应用自适应强度", AutoSize = true, Enabled = false };
    readonly Label adaptiveStatus = new() { Text = "强度：未取得设备上报", AutoSize = true };
    readonly Label adaptiveDraft = new() { Text = "待应用：50%", AutoSize = true };
    readonly Label age = new() { Text = "状态仅代表最后观测，不等于实时保证。", AutoSize = true };
    readonly Label result = new() { Text = "先连接系统蓝牙；然后检测并明确选择目标控制设备。", AutoSize = true, MaximumSize = new Size(740, 0), ForeColor = Color.FromArgb(40, 90, 160) };
    readonly Dictionary<NoiseMode, Button> modes = new();
    readonly Dictionary<string, string> preferences;
    readonly System.Windows.Forms.Timer ticker = new() { Interval = 1000 };
    static string PreferenceFile => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AirPodsBuddyBeta", "models.json");
    Session? session;
    DateTimeOffset? lastEar, lastNoise, lastAdaptive;
    NoiseMode? observedMode;
    bool busy, closing, loadingModel;
    bool receivedNoise;
    bool h2Session;
    bool shutdownDone;
    bool closeRequested;

    public MainForm()
    {
        Text = "AirPods 小助手 · 控制实验室 1.10.0-beta.2";
        ClientSize = new Size(820, 760); MinimumSize = new Size(820, 780);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10);
        BackColor = Color.FromArgb(255, 249, 239);
        ForeColor = Color.FromArgb(67, 53, 30);
        var layout = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(22) };
        Controls.Add(layout);
        Add(new Label { Text = "AirPods 高级控制", Font = new Font(Font.FontFamily, 20, FontStyle.Bold), AutoSize = true });
        Add(new Label { Text = "独立 Beta｜不替换正式版｜不占用麦克风 / 播放流", AutoSize = true, ForeColor = Color.DimGray });
        Row(devices, scan);
        Row(new Label { Text = "设备型号", AutoSize = true, Padding = new Padding(0, 7, 8, 0) }, model);
        Add(identity); Add(experimental); Row(connect, disconnect); Add(channel);
        Add(new Label { Text = "设备状态", AutoSize = true, Font = new Font(Font, FontStyle.Bold) });
        Add(ears); Add(noise); Add(age);
        var buttons = new List<Control>();
        foreach (var (modeValue, label) in new[] { (NoiseMode.Off, "关闭降噪"), (NoiseMode.Anc, "降噪"), (NoiseMode.Transparency, "通透"), (NoiseMode.Adaptive, "自适应 · 实验") })
        {
            NoiseMode chosen = modeValue;
            var button = new Button { Text = label, AutoSize = true, Height = 38, Enabled = false };
            button.Click += async (_, _) => await ChangeModeAsync(chosen);
            modes[chosen] = button; buttons.Add(button);
        }
        Row(buttons.ToArray());
        foreach (var button in new[] { scan, connect, disconnect, applyAdaptive }.Concat(modes.Values))
        {
            button.FlatStyle = FlatStyle.Flat;
            button.BackColor = Color.FromArgb(255, 244, 214);
            button.FlatAppearance.BorderColor = Color.FromArgb(224, 205, 161);
            button.FlatAppearance.MouseOverBackColor = Color.FromArgb(255, 229, 153);
        }
        Add(new Label { Text = "自适应强度 · 仅自适应模式生效（实验）", AutoSize = true, Font = new Font(Font, FontStyle.Bold) });
        Row(new Label { Text = "更多环境声", AutoSize = true, Padding = new Padding(0, 8, 0, 0) }, adaptiveLevel, new Label { Text = "更少环境声", AutoSize = true, Padding = new Padding(0, 8, 0, 0) }, applyAdaptive);
        Row(adaptiveDraft, adaptiveStatus); Add(result);
        adaptiveLevel.ValueChanged += (_, _) => adaptiveDraft.Text = $"待应用：{adaptiveLevel.Value}%";
        applyAdaptive.Click += async (_, _) => await ChangeAdaptiveAsync();
        Add(new Label { Text = "首版只观察入耳状态，不自动暂停 / 恢复媒体。\n主 / 副耳机不等于左 / 右耳。型号自动识别仅依据设备名称，支持手动覆盖。\n模式写入后必须等新状态回读；超时关闭控制通道，不自动重试。\n本包不含驱动、不安装驱动，也不改变蓝牙配对或系统保护设置。\nPro 3 协议兼容与真实听感仍需逐项验收；此通道不解决 HFP 通话音质。", AutoSize = true, ForeColor = Color.DimGray, MaximumSize = new Size(745, 0) });
        preferences = LoadPreferences();
        model.Items.AddRange(Models.Choices); model.SelectedIndex = 0;
        devices.SelectedIndexChanged += (_, _) => LoadModel();
        model.SelectedIndexChanged += (_, _) => SaveModel();
        scan.Click += async (_, _) => await ScanAsync();
        connect.Click += async (_, _) => await ConnectAsync();
        disconnect.Click += async (_, _) => await DisconnectAsync();
        ticker.Tick += (_, _) =>
        {
            string Elapsed(DateTimeOffset? value) => value.HasValue ? $"{(int)(DateTimeOffset.UtcNow - value.Value).TotalSeconds} 秒前" : "从未收到";
            age.Text = $"最近入耳上报：{Elapsed(lastEar)}；最近模式上报：{Elapsed(lastNoise)}；强度：{Elapsed(lastAdaptive)}（非实时保证）";
        };
        ticker.Start();
        FormClosing += async (_, e) =>
        {
            if (shutdownDone) return;
            e.Cancel = true;
            if (busy) { closeRequested = true; Enabled = false; return; }
            if (closing) return;
            closing = true; Enabled = false; ticker.Stop();
            await DisconnectAsync();
            shutdownDone = true; Close();
        };
        UpdateButtons();

        void Add(Control control) { control.Margin = new Padding(0, 0, 0, 8); layout.Controls.Add(control); }
        void Row(params Control[] controls)
        {
            var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 0, 0, 8) };
            row.Controls.AddRange(controls); layout.Controls.Add(row);
        }
    }

    Dictionary<string, string> LoadPreferences()
    {
        try
        {
            if (!File.Exists(PreferenceFile)) return new();
            if (new FileInfo(PreferenceFile).Length > 65536) throw new IOException();
            return JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(PreferenceFile)) ?? new();
        }
        catch { result.Text = "Beta 型号配置读取失败；本次从自动识别开始。"; return new(); }
    }
    void LoadModel()
    {
        loadingModel = true;
        model.SelectedItem = devices.SelectedItem is Device d && preferences.TryGetValue(d.Key, out var choice) && Models.Choices.Contains(choice) ? choice : Models.Choices[0];
        loadingModel = false; ShowIdentity(); UpdateButtons();
    }
    string ResolvedModel => Models.Resolve(model.SelectedItem as string ?? Models.Choices[0], (devices.SelectedItem as Device)?.Name ?? "");
    void ShowIdentity() => identity.Text = $"策略型号：{ResolvedModel}｜{(model.SelectedIndex == 0 ? "名称推测，非硬件认证" : "用户指定，非硬件认证")}";
    void SaveModel()
    {
        ShowIdentity(); UpdateButtons();
        if (loadingModel || devices.SelectedItem is not Device d) return;
        preferences[d.Key] = model.SelectedItem as string ?? Models.Choices[0];
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(PreferenceFile)!);
            string temp = PreferenceFile + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(preferences)); File.Move(temp, PreferenceFile, true);
        }
        catch { result.Text = "型号已用于本次会话，但保存失败。"; }
    }
    void UpdateButtons()
    {
        bool open = session?.IsOpen == true;
        devices.Enabled = model.Enabled = experimental.Enabled = !busy && !open && !closing;
        scan.Enabled = !busy && !open && !closing;
        connect.Enabled = !busy && !open && !closing && devices.SelectedItem is Device;
        disconnect.Enabled = !busy && session != null && !closing;
        foreach (var item in modes) item.Value.Enabled = !busy && !closing && open && receivedNoise && Models.SupportsNoise(ResolvedModel) && (item.Key != NoiseMode.Adaptive || (h2Session && Models.SupportsAdaptive(ResolvedModel)));
        adaptiveLevel.Enabled = applyAdaptive.Enabled = !busy && !closing && open && h2Session && Models.SupportsAdaptive(ResolvedModel) && observedMode == NoiseMode.Adaptive;
    }
    async Task ScanAsync()
    {
        busy = true; UpdateButtons();
        try
        {
            var found = await Task.Run(Driver.Probe);
            devices.Items.Clear(); devices.Items.AddRange(found.Cast<object>().ToArray());
            // Never auto-select the first of several targets.
            if (found.Count == 1) devices.SelectedIndex = 0;
            channel.Text = found.Count == 0 ? "未发现兼容 AAP 接口：可能缺少驱动、耳机未连接或驱动不兼容。" : $"发现 {found.Count} 个控制设备；这不证明音频或控制功能已经就绪。";
            result.Text = found.Count == 0 ? "目前停在驱动 / 控制通道前置条件；不会自动安装驱动。" : "请选择目标，再打开控制通道。";
        }
        catch (Exception e) { SetError("检测失败", e); }
        finally { EndBusy(); }
    }
    async Task ConnectAsync()
    {
        if (devices.SelectedItem is not Device target) return;
        busy = true; UpdateButtons();
        await DisconnectAsync();
        try
        {
            var next = new Session(await Task.Run(() => Driver.Open(target)));
            session = next; h2Session = experimental.Checked;
            next.Observed += report => Post(() => { if (ReferenceEquals(session, next)) Observe(report); });
            next.Ended += message => Post(() => { if (ReferenceEquals(session, next)) { channel.Text = message; ClearObservations(); UpdateButtons(); } });
            await next.StartAsync(h2Session, TimeSpan.FromSeconds(4));
            channel.Text = next.IsOpen ? "控制通道已打开；功能就绪以设备状态回读为准。" : "控制通道已经结束。";
            result.Text = "请戴上 / 取下耳机观察入耳上报；收到模式上报后才开放模式按钮。";
        }
        catch (Exception e) { await DisconnectAsync(); SetError("打开失败", e); }
        finally { EndBusy(); }
    }
    async Task DisconnectAsync()
    {
        var old = session; session = null;
        if (old != null) await old.DisposeAsync();
        ClearObservations(); channel.Text = "控制通道已关闭；未断开系统蓝牙音频。"; UpdateButtons();
    }
    void ClearObservations()
    {
        receivedNoise = false; observedMode = null; lastEar = lastNoise = lastAdaptive = null;
        adaptiveStatus.Text = "强度：未取得设备上报";
        ears.Text = "入耳状态：未知（等待设备上报）"; noise.Text = "降噪模式：未知（等待设备上报）";
    }
    void Observe(Report report)
    {
        if (report is Ears ear)
        {
            string State(EarState value) => value switch { EarState.InEar => "入耳", EarState.Out => "未入耳", _ => "在盒内" };
            ears.Text = $"入耳状态：主耳机 {State(ear.Primary)} · 副耳机 {State(ear.Secondary)}";
            lastEar = DateTimeOffset.UtcNow;
        }
        if (report is Noise modeValue)
        {
            noise.Text = "降噪模式（设备上报）：" + ModeName(modeValue.Mode);
            receivedNoise = true; observedMode = modeValue.Mode; lastNoise = DateTimeOffset.UtcNow;
        }
        if (report is AdaptiveNoise level)
        {
            adaptiveStatus.Text = $"设备上报强度：{level.Level}%";
            lastAdaptive = DateTimeOffset.UtcNow;
        }
        UpdateButtons();
    }
    async Task ChangeAdaptiveAsync()
    {
        if (session is not { IsOpen: true } current || busy || !applyAdaptive.Enabled) return;
        int chosen = adaptiveLevel.Value;
        busy = true; UpdateButtons(); result.Text = "正在发送并等待新的强度状态上报……";
        try
        {
            byte observed = await current.ChangeAdaptiveLevelAsync(chosen, TimeSpan.FromSeconds(4));
            result.Text = observed == chosen ? $"新上报与目标一致：{observed}%。实际环境声变化仍需试听。" : $"回读不一致：请求 {chosen}%，设备上报 {observed}%；未标记成功。";
        }
        catch (OperationCanceledException) { result.Text = "未取得有效强度回读，通道已关闭；未确认成功。"; }
        catch (Exception e) { SetError("强度切换未确认", e); }
        finally { EndBusy(); }
    }
    async Task ChangeModeAsync(NoiseMode modeValue)
    {
        if (session is not { IsOpen: true } current || busy) return;
        busy = true; UpdateButtons(); result.Text = "正在发送并等待新的设备模式上报……";
        try
        {
            var observed = await current.ChangeNoiseAsync(modeValue, TimeSpan.FromSeconds(4));
            result.Text = observed == modeValue ? $"新上报与目标一致：{ModeName(observed)}。请实听确认；上报不证明由本次命令造成。" : $"回读不一致：请求{ModeName(modeValue)}，设备上报{ModeName(observed)}；未标记成功。";
        }
        catch (OperationCanceledException) { result.Text = "未在期限内取得有效回读 / 通道已取消；未确认切换，控制通道已关闭。"; }
        catch (Exception e) { SetError("切换未确认，控制通道已关闭", e); }
        finally { EndBusy(); }
    }
    void EndBusy()
    {
        busy = false; UpdateButtons();
        if (closeRequested && !closing) Close();
    }
    static string ModeName(NoiseMode value) => value switch { NoiseMode.Off => "关闭", NoiseMode.Anc => "降噪", NoiseMode.Transparency => "通透", _ => "自适应" };
    void SetError(string label, Exception error) => result.Text = $"{label}（{error.GetType().Name}，0x{error.HResult:X8}）；未记录设备地址 / 原始报文。";
    void Post(Action action)
    {
        if (closing || IsDisposed || !IsHandleCreated) return;
        try { BeginInvoke(() => { if (!closing && !IsDisposed) action(); }); }
        catch (InvalidOperationException) { }
    }
    public void SaveSmokeImage(string path)
    {
        using var image = new Bitmap(Width, Height); DrawToBitmap(image, new Rectangle(0, 0, Width, Height)); image.Save(path);
    }
    public async Task<string> RunSmokeAsync()
    {
        await ScanAsync();
        if (session != null || modes.Values.Any(x => x.Enabled) || applyAdaptive.Enabled || adaptiveLevel.Enabled) throw new InvalidOperationException("Unexpected hardware access or enabled mode controls");
        return $"UI_SMOKE_PASS version=1.10.0-beta.2 hardwareOpened=false interfaces={devices.Items.Count} modeButtonsEnabled=0 adaptiveEnabled=false";
    }
}
