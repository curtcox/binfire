// binfire host bridge v1 (spec/bridge.md). Single source; tools/configure.mjs
// copies it into every port. Injected only into the main frame of registered
// app origins; native code re-checks the origin on every message.
(function () {
  'use strict';
  if (window.binfire || window.top !== window) return;
  var MAX = 6 * 1024 * 1024;
  var nextId = 1;
  var pending = new Map();

  function transport() {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.binfire) {
      return function (text) { window.webkit.messageHandlers.binfire.postMessage(text); };
    }
    if (window.binfireNative && typeof window.binfireNative.postMessage === 'function') {
      window.binfireNative.onmessage = function (event) { receive(event.data); };
      return function (text) { window.binfireNative.postMessage(text); };
    }
    if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function') {
      return function (text) {
        window.flutter_inappwebview.callHandler('binfire', text).then(function (reply) { if (reply) receive(reply); });
      };
    }
    if (window.ReactNativeWebView && typeof window.ReactNativeWebView.postMessage === 'function') {
      return function (text) { window.ReactNativeWebView.postMessage(text); };
    }
    return null;
  }

  function receive(text) {
    if (typeof text !== 'string' || text.length > MAX) return;
    var message;
    try { message = JSON.parse(text); } catch (e) { return; }
    if (!message || message.v !== 1 || !pending.has(message.id)) return;
    var entry = pending.get(message.id);
    pending.delete(message.id);
    if (typeof message.error === 'string') entry.reject(new Error(message.error));
    else entry.resolve(message.result === undefined ? null : message.result);
  }

  var send = transport();
  if (!send) return;

  Object.defineProperty(window, '__binfireReceive', { value: receive });
  Object.defineProperty(window, 'binfire', {
    value: Object.freeze({
      version: 1,
      request: function (method, params) {
        return new Promise(function (resolve, reject) {
          var id = nextId++;
          var text = JSON.stringify({ v: 1, id: id, method: String(method), params: params || {} });
          if (text.length > MAX) { reject(new Error('too-large')); return; }
          pending.set(id, { resolve: resolve, reject: reject });
          try { send(text); } catch (e) { pending.delete(id); reject(new Error('failed')); }
        });
      },
    }),
  });
  window.dispatchEvent(new Event('binfire:ready'));
})();
