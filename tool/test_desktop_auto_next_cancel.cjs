// Exact prototype functions in a minimal DOM/timer fixture; not a player test.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const sourcePath = path.resolve(process.argv[2] || path.join(__dirname, '../design/desktop/app.js'));
const source = fs.readFileSync(sourcePath, 'utf8');
function between(start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a);
  return source.slice(a, b);
}
const selected = between('let nextCardShown', 'const DANM') +
  between('function openPlayer(id, s, e){', 'function closePlayer(){') +
  between('function drawProgress(){', 'function nudge(sec){') +
  between('function showNextCard(){', '/* ---------- 浮层菜单') +
  source.split('\n').find(line => line.startsWith("$('#plnCancel').onclick ="));
const nodes = new Map(), timers = new Map();
let timerId = 0, nextCalls = 0;
const item = {id: 'synthetic', type: 'tv', hue: [30, 60], title: 'fixture'};
const fixture = {
  $: id => {
    if (!nodes.has(id)) nodes.set(id, {hidden: true, style: {}, classList: {remove() {}},
      querySelector: () => null, insertAdjacentHTML() {}});
    return nodes.get(id);
  },
  player: {t: 81, dur: 100, playing: true, item, chapters: [], curE: 1,
    eps: [{n: 2, title: 'Second'}]},
  chapterAt: () => null, chaptersFor: () => [], fmt: String, art: () => '',
  setInterval: fn => {timers.set(++timerId, fn); return timerId;},
  clearInterval: id => timers.delete(id), setTimeout: () => 0,
  toast() {}, stepEp: () => nextCalls++, byId: () => item,
  epsFor: () => [{n: 1, durSec: 100}, {n: 2, durSec: 100}],
  hidePlMenu() {}, setMini() {}, renderChapters() {}, renderBookmarks() {},
  applyDm() {}, setSpeedLabel() {}, wake() {},
  setPlaying: v => {fixture.player.playing = v;},
};
fixture.player.el = fixture.$('#player');
vm.createContext(fixture);
vm.runInContext(selected, fixture, {filename: sourcePath});
fixture.drawProgress();
assert.equal(fixture.$('#plNextCard').hidden, false);
fixture.$('#plnCancel').onclick();
assert.equal(fixture.$('#plNextCard').hidden, true);
for (let i = 0; i < 20; i++) {fixture.player.t++; fixture.drawProgress();}
assert.equal(fixture.$('#plNextCard').hidden, true, 'cancel survives later progress ticks');
assert.equal(timers.size, 0);
fixture.player.playing = false; fixture.drawProgress();
fixture.player.playing = true; fixture.drawProgress();
fixture.seek(0); fixture.seek(95);
assert.equal(fixture.$('#plNextCard').hidden, true, 'pause/resume and seek do not undo cancel');
assert.equal(nextCalls, 0);
fixture.openPlayer(item.id, 1, 2);
fixture.seek(95);
assert.equal(fixture.$('#plNextCard').hidden, false, 'new episode can show countdown');
for (let i = 0; i < 10; i++) for (const fn of [...timers.values()]) fn();
assert.equal(nextCalls, 1);
assert.equal(timers.size, 0);
process.stdout.write(JSON.stringify({result: 'PASS', prototype_only: true,
  checks: ['cancel', '20 ticks', 'pause/resume', 'seek', 'new episode', 'countdown', 'timer cleanup'],
  source: sourcePath, player_runtime_tested: false}) + '\n');
