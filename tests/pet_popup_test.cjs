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
  const fire = (delay) => {
    const [id, timer] = (delay===undefined?timers.entries().next().value:[...timers.entries()].find(([,t])=>t.delay===delay)) || [];
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
  assert.equal(p.timers.size,0,'hidden pet does not animate');
  p.window.showPopup();
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

  // The 49 cells are one ordered action and stop at the completed pose.
  const frameOf = pos => { const [col,row] = [...pos.matchAll(/-(\d+)px/g)].map(x=>Number(x[1])/150); return row*7+col; };
  assert.equal(frameOf(currentFrame),1);
  for(let i=2;i<=48;i++){p.fire(); assert.equal(frameOf(p.elements.sprite.style.backgroundPosition),i);}
  assert.equal(p.timers.size,1,'next wait-loop is scheduled');
  p.fire();assert.match(p.elements.sprite.style.backgroundImage,/headphones-wait-49/);
  assert.equal(frameOf(p.elements.sprite.style.backgroundPosition),0);
  for(let i=1;i<=48;i++){p.fire();assert.equal(frameOf(p.elements.sprite.style.backgroundPosition),i);}
  p.fire();assert.equal(frameOf(p.elements.sprite.style.backgroundPosition),47);
  console.log('PASS headphones_49_frame_order_and_wait_loop');

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
  assert.match(p.elements.sprite.style.backgroundImage,/headphones-fail-49/);
  for(let i=1;i<=20;i++)p.fire();
  assert.equal(frameOf(p.elements.sprite.style.backgroundPosition),20);
  p.fire();assert.match(p.elements.sprite.style.backgroundImage,/headphones-wait-49/);
  assert.equal(p.timers.size,1,'disconnect failure continues wearing loop');
  p.window.setState('off');
  assert.equal(p.elements.bubbleDetail.textContent, '设备已断开');
  assert.match(p.elements.sprite.style.backgroundImage,/headphones-idle-49/);
  assert.equal(p.timers.size,1,'terminal off pose continues idle while visible');
  p.window.setState('connecting');
  assert.equal(p.timers.size,1);p.window.hidePopup();assert.equal(p.timers.size,0);
  p.window.showPopup();assert.equal(p.timers.size,1);p.window.hidePopup();
  console.log('PASS hidden_pet_cancels_frames_and_resumes_on_show');
  console.log('PASS terminal_animation_stops_and_text_is_plain');

  const early=boot();early.window.showPopup();early.window.setState('connecting');
  early.fire(50);early.fire(50);early.window.setState('ok');
  assert.match(early.elements.sprite.style.backgroundImage,/headphones-49/);
  for(let i=3;i<=48;i++)early.fire(50);early.fire(50);
  assert.match(early.elements.sprite.style.backgroundImage,/headphones-wait-49/);
  early.window.setState('disconnecting');assert.equal(frameOf(early.elements.sprite.style.backgroundPosition),48);
  early.fire(50);early.window.setState('off');
  assert.match(early.elements.sprite.style.backgroundImage,/headphones-49/);
  for(let i=46;i>=0;i--)early.fire(50);early.fire(50);
  assert.match(early.elements.sprite.style.backgroundImage,/headphones-idle-49/);
  early.window.hidePopup();assert.equal(early.timers.size,0);
  console.log('PASS early_terminal_preserves_action_then_continuous_idle');

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
