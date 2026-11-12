// 明文和桌面之间只有一条通道：ais6-bridge.js。在桌面里，它向宿主问好、拿到
// 端口；单独打开这一页时，它换成独立适配器（存档在本页自己的存储里）。
// 存档整份读进来以后才开始游戏，所以引擎里的读取仍然是同步的。
(function () {
  'use strict';
  var VERSION = '1.0.0';

  function loadState(bridge) {
    return bridge.call('state.keys', {}).then(function (answer) {
      var keys = (answer && answer.keys) || [], saved = {};
      return Promise.all(keys.map(function (key) {
        return bridge.call('state.get', { key: key }).then(function (got) { saved[key] = got ? got.value : null; });
      })).then(function () { return saved; });
    });
  }

  function start(bridge, saved) { window.PlainStart(bridge, saved); }

  window.AIS6Bridge.connect({ appId: 'mingwen', window: 'mingwen', version: VERSION, applyAppearance: false }).then(function (bridge) {
    return loadState(bridge).then(function (saved) { start(bridge, saved); }, function () { start(bridge, null); });
  }, function () { start(null, null); });
})();
