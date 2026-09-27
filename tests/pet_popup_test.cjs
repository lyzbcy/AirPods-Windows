const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const mode = process.argv[2] || '--modified';
const path = process.argv[3] || 'webui/pet.html';
const html = fs.readFileSync(path, 'utf8');

function boot(reduced = false) {
  const timers = new Map();
  let nextId = 0;
  const elements = Object.fromEntries(['stage', 'sprite', 'bubble', 'bubbleTitle', 'bubbleDetail']
    .map(id => [id, {id, style: {}, className: '', textContent: '', hidden: false}]));
  const card = {appendChild() {}};
  const window = {matchMedia: () => ({matches: reduced, addEventListener() {}})};
  const document = {
    getElementById: id => elements[id],
    querySelector: () => card,
    createElement: () => ({style: {}, remove() {}}),
  };
  const context = vm.createContext({window, document, chrome: {webview: {postMessage() {}}},
    setTimeout: (fn, delay) => {const id = ++nextId; timers.set(id, {fn, delay}); return id;},
    clearTimeout: id => timers.delete(id)});
  const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
  assert.ok(script, 'pet script exists');
  vm.runInContext(script, context);
  const fire = () => {
    const [id, timer] = timers.entries().next().value || [];
    assert.ok(timer, 'timer available');
    timers.delete(id); timer.fn();
  };
  return {window, elements, timers, fire};
}

if (mode === '--baseline') {
  const p = boot();
  p.window.setState('connecting');
  assert.equal(p.elements.bubble.textContent, '连接中');
  assert.equal(p.elements.bubble.className, 'bubble dots');
  p.window.showPopup();
  assert.equal(p.elements.stage.className, 'stage in');
  p.window.hidePopup();
  assert.equal(p.elements.stage.className, 'stage out');
  console.log('BASELINE_PASS legacy_pet_contract');
} else {
  if (!/window\.setProgress\s*=/.test(html)) {
    console.error('FAIL progress_two_lines_and_elapsed: setProgress API missing');
    process.exit(1);
  }
  assert.match(html, /id="bubbleTitle"/);
  assert.match(html, /id="bubbleDetail"[^>]*aria-live="off"/);
  assert.match(html, /prefers-reduced-motion: reduce/);
  const p = boot();
  p.window.setProgress({state: 'connecting', phaseText: '正在核实链路', elapsedMs: 2500});
  assert.equal(p.elements.bubbleTitle.textContent, '连接中');
  assert.equal(p.elements.bubbleDetail.textContent, '正在核实链路 · 已等待 2 秒');
  assert.equal(p.elements.bubbleDetail.hidden, false);
  assert.equal(p.elements.bubbleTitle.className, 'bubble-title dots');
  console.log('PASS progress_two_lines_and_elapsed');

  p.fire();
  const currentFrame = p.elements.sprite.style.backgroundPosition;
  const timerCount = p.timers.size;
  p.window.setProgress({state: 'connecting', phaseText: '仍在核实', elapsedMs: 3200});
  assert.equal(p.elements.sprite.style.backgroundPosition, currentFrame);
  assert.equal(p.timers.size, timerCount);
  assert.equal(p.elements.bubbleDetail.textContent, '仍在核实 · 已等待 3 秒');
  console.log('PASS progress_update_does_not_restart_animation');

  const loop = [currentFrame];
  for (let i = 0; i < 9; i++) {p.fire(); loop.push(p.elements.sprite.style.backgroundPosition);}
  assert.deepEqual(loop.map(pos => Number(pos.match(/-(\d+)px/)[1]) / 150),
    [1, 4, 3, 2, 5, 2, 3, 4, 1, 0]);
  console.log('PASS waiting_loop_uses_pose_bridge');

  p.window.setState('disconnecting', '正在断开设备');
  assert.equal(p.elements.bubbleTitle.textContent, '断开中');
  assert.equal(p.elements.bubbleDetail.textContent, '正在断开设备');
  p.window.setProgress({state: 'disconnecting', phaseText: '<b>原样文本</b>', elapsedMs: -1});
  assert.equal(p.elements.bubbleDetail.textContent, '<b>原样文本</b>');
  p.window.setState('fail', '断开状态尚未确认');
  assert.equal(p.elements.bubbleTitle.textContent, '断开未完成');
  assert.equal(p.elements.bubbleDetail.textContent, '断开状态尚未确认');
  p.window.setState('fail', '正在重新核实');
  assert.equal(p.elements.bubbleTitle.textContent, '断开未完成');
  p.window.setState('off');
  assert.equal(p.elements.bubbleDetail.textContent, '设备已断开');
  for (let i = 0; i < 3; i++) p.fire();
  assert.equal(p.timers.size, 0, 'terminal waving animation stops after one pass');
  console.log('PASS terminal_animation_stops_and_text_is_plain');

  const quiet = boot(true);
  assert.equal(quiet.timers.size, 0);
  quiet.window.setProgress({state: 'connecting', phaseText: '正在连接', elapsedMs: 0});
  assert.equal(quiet.timers.size, 0);
  quiet.window.setState('ok');
  assert.equal(quiet.timers.size, 0);
  assert.equal(quiet.elements.bubbleTitle.textContent, '连接已就绪');
  assert.equal(quiet.elements.bubbleDetail.textContent, '请试听确认声音');
  console.log('PASS reduced_motion_freezes_sprite_and_hearts');
}
