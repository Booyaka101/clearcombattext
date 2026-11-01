const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const assert = require('node:assert/strict');
const { lua, lauxlib } = fengari;

const here = __dirname;
const read = (p) => fs.readFileSync(path.join(here, p), 'utf8');
const prelude = read('prelude.lua');
const toc = fs.readFileSync(path.join(here, '..', '..', 'ClearCombatText.toc'), 'utf8');
assert.match(toc, /^## Category: Combat\r?$/m, 'native combat category missing');
const addon = toc.split(/\r?\n/).filter(line => line.endsWith('.lua'))
  .map(file => `assert(load(${JSON.stringify(fs.readFileSync(path.join(here, '..', '..', file), 'utf8'))}, ${JSON.stringify('@' + file)}))('ClearCombatText', ADDON)`)
  .join('\n');

function run(name, setup, driver, savedVariables = '', source = addon) {
  const program = prelude + '\nADDON = {}\n' + setup + '\n' + source + '\n' + savedVariables + '\n' + driver;
  const L = lua.lua_newstate();
  fengari.lualib.luaL_openlibs(L);
  try {
    const status = lauxlib.luaL_dostring(L, fengari.to_luastring(program));
    if (status !== lua.LUA_OK) {
      const err = lua.lua_tostring(L, -1);
      throw new Error(`${name}: ${err ? fengari.to_jsstring(err) : 'unknown'}`);
    }
  } finally {
    lua.lua_close(L);
  }
}

run('pipeline', '', read('driver.lua'));
run('regressions', '', read('regressions.lua'));
run('settings and layout', '', read('settings.lua'));
run('render review', '', read('review.lua'));
run('UI review', '', read('ui-review.lua'));

for (const [name, setup] of Object.entries({
  missingNamespace: 'C_CombatText=nil',
  missingMethods: 'C_CombatText={}',
  invalidMethods: 'C_CombatText={SetActiveUnit=true,GetCurrentEventInfo=true}',
  missingBinding: 'C_CombatText.SetActiveUnit=nil',
  missingPayload: 'C_CombatText.GetCurrentEventInfo=nil',
  invalidBinding: 'C_CombatText.SetActiveUnit=true',
  invalidPayload: 'C_CombatText.GetCurrentEventInfo=true',
})) {
  run(name, `local originalCombatText={SetActiveUnit=C_CombatText.SetActiveUnit,GetCurrentEventInfo=C_CombatText.GetCurrentEventInfo}\n${setup}`, read('api-compatibility.lua'));
  console.log(`API COMPATIBILITY PASSED: ${name}`);
}

const position = (x, direction) => `{point="CENTER",relPoint="CENTER",x=${x},y=100,direction="${direction}"}`;
const scenarios = {
  left: 'ClearCombatTextDB={anchor={point="LEFT",relPoint="LEFT",x=-50,y=200}}',
  right: 'ClearCombatTextDB={anchor={point="RIGHT",relPoint="RIGHT",x=-50,y=200}}',
  corner: 'ClearCombatTextDB={anchor={point="TOPLEFT",relPoint="TOPLEFT",x=-50,y=200}}',
  saved: `ClearCombatTextDB={streams={incoming=${position(222, 'down')},gains=${position(333, 'left')}}}`,
  partial: `ClearCombatTextDB={anchor=${position(-50, 'up')},streams={incoming=${position(222, 'down')}}}`,
  invalidRoot: 'ClearCombatTextDB=true',
  invalidStreams: 'ClearCombatTextDB={streams=true}',
  invalidEntries: 'ClearCombatTextDB={streams={incoming=true,gains="bad"},anchor={point="BAD",x=0,y=0}}',
  invalidNumbers: 'ClearCombatTextDB={streams={incoming={point="CENTER",relPoint="CENTER",x=0/0,y=0},gains={point="CENTER",relPoint="CENTER",x=math.huge,y=0}}}',
  savedOptions: 'ClearCombatTextDB={options={enabled=false,fontScale=1.5,filters={auras=false},incoming={duration=3.2}}}',
  invalidOptions: 'ClearCombatTextDB={options={fontScale=0/0,opacity=math.huge,filters=true,incoming=true},profiles=true}',
};
for (const [name, setup] of Object.entries(scenarios)) {
  // WoW restores persisted variables after addon code, before login events.
  run(name, '', read('startup.lua'), `CASE="${name}"\n${setup}`);
}

if (process.argv.includes('--mutations')) {
  const mutations = [
    ['capacity bypass', 'count >= area.maxLines', 'false'],
    ['priority disabled', 'entry.priority < importance', 'false'],
    ['spacing removed', 'distance + a.height + a.spacing', 'distance + 1'],
    ['consolidation rewind', 'p.entry.fs:SetText(text)', 'p.entry.fs:SetText(text); p.entry.born = now'],
    ['disabled events allowed', '(options.enabled or preview)', 'true'],
    ['aliased profile snapshot', 'options = addon.NormalizeOptions(addon.GetOptions())', 'options = addon.GetOptions()'],
    ['slider synchronization disabled', 'syncing = true', 'syncing = false'],
    ['expiry disabled', 'if now - active[i].born >= active[i].duration then discard(i) end', 'if false then discard(i) end', 'review.lua'],
    ['sliding consolidation window', 'p.n = p.n + 1', 'p.t = now; p.n = p.n + 1', 'review.lua'],
    ['panel scaling disabled', 'panel:SetScale(math.min(1,', 'panel:SetScale(math.max(1,', 'ui-review.lua'],
    ['profile confirmation bypassed', 'and addon.HasProfile(name)', 'and false', 'ui-review.lua'],
    ['draft protection disabled', 'if dirty or e:HasFocus() then return end', '', 'ui-review.lua'],
    ['preview priority isolation removed', 'if preview then importance = importance - 4 end', '', 'review.lua'],
    ['preview cleanup removed', 'if active[i].preview then discard(i) end', '', 'review.lua'],
  ];
  for (const [name, before, after, driver = 'settings.lua'] of mutations) {
    assert.ok(addon.includes(before), `mutation target missing: ${name}`);
    assert.throws(() => run(name, '', read(driver), '', addon.replace(before, after)),
      /ASSERT FAILED:|filtered event fetched payload|stack (?:overflow|size exceeded)/i, `mutation survived or failed for an unrelated reason: ${name}`);
    console.log(`MUTATION CAUGHT: ${name}`);
  }
}
