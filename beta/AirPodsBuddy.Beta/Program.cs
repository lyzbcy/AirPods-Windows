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
                File.WriteAllText(args[1], JsonSerializer.Serialize(new { version = "1.10.0-beta.3", interfaces = count, opened = false, settingsChanged = false }));
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
    readonly WarmSelect devices = new() { Placeholder = "未检测到兼容接口", Width = 245 };
    readonly WarmSelect model = new() { Placeholder = "请选择型号", Width = 240 };
    readonly Button scan = new WarmButton() { Text = "检测控制通道", AutoSize = true };
    readonly Button connect = new WarmButton() { Text = "打开控制通道", AutoSize = true };
    readonly Button disconnect = new WarmButton() { Text = "关闭控制通道", AutoSize = true, Enabled = false };
    readonly WarmToggle experimental = new() { Text = "启用 H2 实验能力（本次连接）", AutoSize = false };
    readonly Label channel = new() { Text = "尚未检测。普通蓝牙连接 ≠ AAP 控制通道可用。", AutoSize = true, MaximumSize = new Size(740, 0) };
    readonly Label identity = new() { Text = "型号：未知", AutoSize = true, MaximumSize = new Size(740, 0) };
    readonly Label ears = new() { Text = "入耳状态：未知（等待设备上报）", AutoSize = true };
    readonly Label noise = new() { Text = "降噪模式：未知（等待设备上报）", AutoSize = true };
    readonly WarmSlider adaptiveLevel = new() { Value = 50, Width = 240, Height = 34, Enabled = false };
    readonly Button applyAdaptive = new WarmButton() { Text = "应用自适应强度", AutoSize = true, Enabled = false };
    readonly Label adaptiveStatus = new() { Text = "强度：未取得设备上报", AutoSize = true };
    readonly Label adaptiveDraft = new() { Text = "待应用：50%", AutoSize = true };
    readonly Label age = new() { Text = "状态为最后观测，不是实时保证。", AutoSize = true };
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
        Text = "AirPods 小助手 · 控制实验室 1.10.0-beta.3";
        ClientSize = new Size(820, 700); MinimumSize = new Size(820, 700);
        StartPosition = FormStartPosition.CenterScreen; FormBorderStyle = FormBorderStyle.None;
        AutoScaleMode = AutoScaleMode.None;
        Font = new Font("Microsoft YaHei UI", 14, FontStyle.Regular, GraphicsUnit.Pixel);
        BackColor = Color.FromArgb(255, 247, 232);
        ForeColor = Color.FromArgb(67, 53, 30);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3, Padding = new Padding(16), BackColor = BackColor };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 48));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 52));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 132));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 66));
        Controls.Add(layout);
        var header = new WarmCard { Dock = DockStyle.Fill, Margin = new Padding(0,0,0,10), Padding = new Padding(18,14,18,10) };
        var title = new Label { Text = "降噪 / 通透 · 控制实验室", Font = new Font(Font.FontFamily, 24, FontStyle.Bold, GraphicsUnit.Pixel), AutoSize = true, Location = new Point(18,12) };
        var badge = new Label { Text = "独立实验 · 硬件能力未验证", AutoSize = true, ForeColor = Color.FromArgb(145,77,36), Location = new Point(18,47) };
        var explanation = new Label { Text = "已经实现协议与会话代码；本机仍需兼容 AAP 驱动。无接口就不能控制耳机。\n正规微软签名需要企业资质、EV 证书与审核；非正规途径会降低系统安全。", AutoSize = true, MaximumSize = new Size(690,0), Location = new Point(18,70) };
        var minimize = new WarmButton { Text = "—", AutoSize=false, MinimumSize=Size.Empty, Width = 38, Height = 34, Anchor = AnchorStyles.Top|AnchorStyles.Left };
        var close = new WarmButton { Text = "×", AutoSize=false, MinimumSize=Size.Empty, Width = 38, Height = 34, Anchor = AnchorStyles.Top|AnchorStyles.Left };
        header.Controls.AddRange(new Control[]{title,badge,explanation,minimize,close});
        void PlaceHeaderButtons(){close.Location=new Point(header.Width-50,10);minimize.Location=new Point(header.Width-94,10);}
        header.Resize += (_,_) => PlaceHeaderButtons();
        Shown += (_,_) => PlaceHeaderButtons();
        minimize.Click += (_,_) => WindowState=FormWindowState.Minimized; close.Click += (_,_) => Close();
        Point drag=Point.Empty; bool dragging=false;
        title.MouseDown+=(_,e)=>{if(e.Button==MouseButtons.Left){drag=Cursor.Position;dragging=true;}};
        title.MouseMove+=(_,_)=>{if(dragging){var now=Cursor.Position;Location=new Point(Location.X+now.X-drag.X,Location.Y+now.Y-drag.Y);drag=now;}};
        title.MouseUp+=(_,_)=>dragging=false;
        layout.Controls.Add(header,0,0);layout.SetColumnSpan(header,2);
        var left=PanelColumn();var right=PanelColumn();
        layout.Controls.Add((Control)left.Tag!,0,1);layout.Controls.Add((Control)right.Tag!,1,1);
        Section(left,"01  ·  控制通道","先连接 Windows 蓝牙，再检查已有兼容接口");
        devices.Width=245;model.Width=240;
        devices.BackColor=model.BackColor=Color.FromArgb(255,253,246);
        devices.ForeColor=model.ForeColor=ForeColor;
        Add(left,devices);Row(left,scan);
        Section(left,"目标型号","仅是协议策略，不代表硬件认证");
        Add(left,model);Add(left,identity);
        experimental.MaximumSize=new Size(340,0);Add(left,experimental);Row(left,connect,disconnect);Add(left,channel);
        Section(right,"02  ·  状态与控制","先取得设备回读，才解锁控制");
        Add(right,ears);Add(right,noise);Add(right,age);
        var buttons = new List<Control>();
        foreach (var (modeValue, label) in new[] { (NoiseMode.Off, "关闭降噪"), (NoiseMode.Anc, "降噪"), (NoiseMode.Transparency, "通透"), (NoiseMode.Adaptive, "自适应") })
        {
            NoiseMode chosen = modeValue;
            var button = new WarmButton { Text = label, AutoSize = true, Height = 36, Enabled = false };
            button.Click += async (_, _) => await ChangeModeAsync(chosen);
            modes[chosen] = button;buttons.Add(button);
        }
        Row(right,buttons.ToArray());
        Section(right,"03  ·  自适应强度","仅在设备上报自适应后可用");
        Add(right,adaptiveLevel);Row(right,adaptiveDraft,applyAdaptive);Add(right,adaptiveStatus);
        var foot = new WarmCard { Dock=DockStyle.Fill, Margin=new Padding(0,10,0,0), Padding=new Padding(14,9,14,9) };
        result.Dock=DockStyle.Fill;result.AutoSize=false;result.MaximumSize=Size.Empty;
        result.ForeColor=Color.FromArgb(110,81,39);foot.Controls.Add(result);
        layout.Controls.Add(foot,0,2);layout.SetColumnSpan(foot,2);
        adaptiveLevel.ValueChanged += (_, _) => adaptiveDraft.Text = $"待应用：{adaptiveLevel.Value}%";
        // Keep the safety/compatibility summary in the first screen, not a hidden scroll tail.
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

        FlowLayoutPanel PanelColumn() {
            var card=new WarmCard {Dock=DockStyle.Fill,Margin=new Padding(4),Padding=new Padding(12)};
            // Wrap long labels inside each column; scrolling is a fallback only.
            var panel=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=false,BackColor=Color.FromArgb(255,253,247)};
            card.Controls.Add(panel);
            // Table owns the outer card; return its content while placing the card itself.
            panel.Tag=card;return panel;
        }
        void Section(FlowLayoutPanel panel,string titleText,string note) {
            Add(panel,new Label { Text=titleText,AutoSize=true,Font=new Font(Font.FontFamily,17,FontStyle.Bold,GraphicsUnit.Pixel)});
            Add(panel,new Label {Text=note,AutoSize=true,ForeColor=Color.FromArgb(143,117,78)});
        }
        void Add(FlowLayoutPanel panel,Control control) {
            control.Margin=new Padding(0,0,0,6);
            if(control is Label label){label.MaximumSize=new Size(340,0);label.AutoSize=true;}
            panel.Controls.Add(control);
        }
        void Row(FlowLayoutPanel panel,params Control[] controls) {
            var row=new FlowLayoutPanel {AutoSize=true,WrapContents=true,MaximumSize=new Size(350,0),Margin=new Padding(0,0,0,6)};
            row.Controls.AddRange(controls);panel.Controls.Add(row);
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
            devices.ClearItems(); devices.Items.AddRange(found.Cast<object>().ToArray());
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
    static void CheckBounds(Control parent){
        foreach(Control child in parent.Controls){
            if(child.Visible && (child.Left<0||child.Top<0||child.Right>parent.ClientSize.Width+1||child.Bottom>parent.ClientSize.Height+1))
                throw new InvalidOperationException("Control outside layout: "+child.GetType().Name);
            CheckBounds(child);
        }
    }

    public async Task<string> RunSmokeAsync()
    {
        await ScanAsync();
        if (session != null || modes.Values.Any(x => x.Enabled) || applyAdaptive.Enabled || adaptiveLevel.Enabled) throw new InvalidOperationException("Unexpected hardware access or enabled mode controls");
        CheckBounds(this);
        return $"UI_SMOKE_PASS layoutContained=true version=1.10.0-beta.3 hardwareOpened=false interfaces={devices.Items.Count} modeButtonsEnabled=0 adaptiveEnabled=false";
    }
}


sealed class WarmCard : Panel {
    public WarmCard(){DoubleBuffered=true;BackColor=Color.FromArgb(255,253,247);Resize+=(_,_)=>Invalidate();}
    protected override void OnPaintBackground(PaintEventArgs e){e.Graphics.Clear(Parent?.BackColor??Color.FromArgb(255,247,232));using var b=new SolidBrush(BackColor);using var path=WarmShape.Path(ClientRectangle,26);e.Graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;e.Graphics.FillPath(b,path);}
}
static class WarmShape {
    public static System.Drawing.Drawing2D.GraphicsPath Path(Rectangle r,int radius){
        var p=new System.Drawing.Drawing2D.GraphicsPath();int d=Math.Max(1,Math.Min(radius*2,Math.Min(r.Width,r.Height)));int x=r.X,y=r.Y,w=r.Width,h=r.Height;
        p.AddArc(x,y,d,d,180,90);p.AddArc(x+w-d,y,d,d,270,90);p.AddArc(x+w-d,y+h-d,d,d,0,90);p.AddArc(x,y+h-d,d,d,90,90);p.CloseFigure();return p;
    }
}
class WarmButton : Button {
    bool hover;
    public WarmButton(){FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;AutoSize=true;MinimumSize=new Size(72,32);Padding=new Padding(9,2,9,2);Cursor=Cursors.Hand;SetStyle(ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer,true);}
    protected override void OnMouseEnter(EventArgs e){hover=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hover=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnEnabledChanged(EventArgs e){Invalidate();base.OnEnabledChanged(e);}
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.Clear(Parent?.BackColor??Color.FromArgb(255,253,247));e.Graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        var r=ClientRectangle;r.Inflate(-1,-1);using var p=WarmShape.Path(r,20);using var b=new SolidBrush(!Enabled?Color.FromArgb(237,231,219):hover?Color.FromArgb(255,211,95):Color.FromArgb(255,232,169));e.Graphics.FillPath(b,p);
        TextRenderer.DrawText(e.Graphics,Text,Font,r,Enabled?Color.FromArgb(67,53,30):Color.FromArgb(151,140,118),TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis);
        if(Focused&&Enabled)ControlPaint.DrawFocusRectangle(e.Graphics,Rectangle.Inflate(r,-5,-5));
    }
}
sealed class WarmSlider : Control {
    int value=50;public event EventHandler? ValueChanged;
    public int Value {get=>value;set{int v=Math.Clamp(value,0,100);if(this.value!=v){this.value=v;Invalidate();ValueChanged?.Invoke(this,EventArgs.Empty);}}}
    public WarmSlider(){SetStyle(ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.Selectable,true);TabStop=true;AccessibleName="自适应强度";}
    protected override void OnPaint(PaintEventArgs e){e.Graphics.Clear(Parent?.BackColor??Color.White);e.Graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;int x=12+(Width-24)*Value/100;using var track=new Pen(Color.FromArgb(230,218,192),7);track.StartCap=track.EndCap=System.Drawing.Drawing2D.LineCap.Round;e.Graphics.DrawLine(track,12,Height/2,Width-12,Height/2);using var thumb=new SolidBrush(Enabled?Color.FromArgb(255,195,61):Color.FromArgb(174,164,145));e.Graphics.FillEllipse(thumb,x-8,Height/2-8,16,16);}
    protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);if(Enabled){Focus();Capture=true;Value=(e.X-12)*100/Math.Max(1,Width-24);}}
    protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);if(Enabled&&Capture)Value=(e.X-12)*100/Math.Max(1,Width-24);}
    protected override void OnMouseUp(MouseEventArgs e){Capture=false;base.OnMouseUp(e);}
    protected override bool IsInputKey(Keys keyData)=>keyData==Keys.Left||keyData==Keys.Right||base.IsInputKey(keyData);
    protected override void OnKeyDown(KeyEventArgs e){if(Enabled&&e.KeyCode==Keys.Left)Value--;else if(Enabled&&e.KeyCode==Keys.Right)Value++;base.OnKeyDown(e);}
    protected override void OnEnabledChanged(EventArgs e){Invalidate();base.OnEnabledChanged(e);}
}


sealed class WarmSelect : WarmButton {
    int index=-1;
    public List<object> Items {get;}=new();
    public string Placeholder {get;set;}="请选择";
    public event EventHandler? SelectedIndexChanged;
    public int SelectedIndex {get=>index;set{int next=value>=0&&value<Items.Count?value:-1;if(index!=next){index=next;RefreshLabel();SelectedIndexChanged?.Invoke(this,EventArgs.Empty);}else RefreshLabel();}}
    public object? SelectedItem {get=>index>=0&&index<Items.Count?Items[index]:null;set=>SelectedIndex=Items.IndexOf(value!);}
    public WarmSelect(){AutoSize=false;Height=36;AccessibleRole=AccessibleRole.ComboBox;Click+=(_,_)=>OpenChoices();}
    public void ClearItems(){Items.Clear();index=-1;RefreshLabel();SelectedIndexChanged?.Invoke(this,EventArgs.Empty);}
    void RefreshLabel(){Text=(SelectedItem?.ToString()??Placeholder)+"  ▾";Invalidate();}
    protected override void OnCreateControl(){base.OnCreateControl();RefreshLabel();}
    void OpenChoices(){
        if(Items.Count==0)return;
        var menu=new ContextMenuStrip{ShowImageMargin=false,BackColor=Color.FromArgb(255,249,235),ForeColor=Color.FromArgb(67,53,30),Font=Font,Renderer=new ToolStripProfessionalRenderer(new WarmColors())};
        for(int i=0;i<Items.Count;i++){int selected=i;var item=new ToolStripMenuItem(Items[i].ToString()??""){Checked=i==index};item.Click+=(_,_)=>SelectedIndex=selected;menu.Items.Add(item);}
        menu.Closed+=(_,_)=>menu.Dispose();menu.Show(this,new Point(0,Height));
    }
}
sealed class WarmColors : ProfessionalColorTable {
    public override Color ToolStripDropDownBackground=>Color.FromArgb(255,249,235);
    public override Color MenuItemSelected=>Color.FromArgb(255,228,150);
    public override Color MenuItemBorder=>Color.FromArgb(225,191,111);
    public override Color MenuBorder=>Color.FromArgb(225,191,111);
}

sealed class WarmToggle : WarmButton {
    bool selected;
    public bool Checked {get=>selected;set{selected=value;Invalidate();}}
    public WarmToggle(){AutoSize=false;Width=300;Height=32;AccessibleRole=AccessibleRole.CheckButton;Click+=(_,_)=>Checked=!Checked;}
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.Clear(Parent?.BackColor??Color.FromArgb(255,253,247));e.Graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        var track=new Rectangle(0,6,40,20);using var path=WarmShape.Path(track,10);using var b=new SolidBrush(Checked?Color.FromArgb(112,158,103):Color.FromArgb(217,208,190));e.Graphics.FillPath(b,path);
        using var thumb=new SolidBrush(Color.White);e.Graphics.FillEllipse(thumb,Checked?22:3,9,14,14);
        TextRenderer.DrawText(e.Graphics,Text,Font,new Rectangle(48,0,Width-48,Height),Enabled?Color.FromArgb(67,53,30):Color.FromArgb(151,140,118),TextFormatFlags.Left|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.SingleLine);
        if(Focused&&Enabled)ControlPaint.DrawFocusRectangle(e.Graphics,ClientRectangle);
    }
}
