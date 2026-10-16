const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { lua, lauxlib } = fengari;

const here = __dirname;
const read = (p) => fs.readFileSync(path.join(here, p), 'utf8');
const prelude = read('prelude.lua');
const addon = fs.readFileSync(path.join(here, '..', '..', 'ClearCombatText.lua'), 'utf8');

function run(name, setup, driver, savedVariables = '') {
  const program = prelude + '\n' + setup + '\ndo\n' + addon + '\nend\n' + savedVariables + '\n' + driver;
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
};
for (const [name, setup] of Object.entries(scenarios)) {
  // WoW restores persisted variables after addon code, before login events.
  run(name, '', read('startup.lua'), `CASE="${name}"\n${setup}`);
}
