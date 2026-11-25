const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync('webui/tray.html','utf8');
const code=html.slice(html.indexOf('<script>')+8,html.lastIndexOf('</script>'));
const posted=[],handlers={},nodes={stateText:{},stateLed:{dataset:{}},logCheck:{}};
const buttons=['open','connect','disconnect','advanced','logs','update','feedback','quit','close'].map(action=>({dataset:{action},addEventListener:(_,fn)=>handlers[action]=fn}));
const ctx={chrome:{webview:{postMessage:m=>posted.push(m)}},document:{querySelectorAll:()=>buttons,getElementById:id=>nodes[id],addEventListener:(event,fn)=>handlers[event]=fn},window:{}};
vm.createContext(ctx);vm.runInContext(code,ctx);
assert.deepEqual(posted,['tray:ready']);console.log('PASS tray_initialization_is_read_only');
ctx.window.setTrayState(true,false,true);assert.equal(nodes.stateLed.dataset.state,'on');assert.equal(nodes.logCheck.textContent,'✓');
ctx.window.setTrayState(false,true,false);assert.equal(nodes.stateLed.dataset.state,'busy');console.log('PASS tray_indicators_follow_host_truth');
handlers.open();handlers.connect();assert.deepEqual(posted,['tray:ready','tray:open']);console.log('PASS tray_actions_single_dispatch');
ctx.window.setTrayState(false,false,false);handlers.keydown({key:'Escape'});assert.equal(posted.at(-1),'tray:close');console.log('PASS tray_escape_closes_without_action');
// The report entry is spelled out in the menu and posts exactly one whitelisted action.
assert.match(html,/<button data-action="feedback">[\s\S]*?<\/svg>遇到问题反馈<span/);
ctx.window.setTrayState(false,false,false);handlers.feedback();assert.equal(posted.at(-1),'tray:feedback');handlers.feedback();assert.equal(posted.at(-1),'tray:feedback');
console.log('PASS tray_report_entry_is_first_level_and_single_dispatch');
assert.match(html,/prefers-reduced-motion/);assert.doesNotMatch(html,/https?:\/\//);console.log('PASS tray_local_and_reduced_motion');
