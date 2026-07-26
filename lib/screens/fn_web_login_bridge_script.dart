import 'dart:convert';

class FnWebLoginBridgeScript {
  const FnWebLoginBridgeScript._();

  static String build({
    required String bridgeName,
    required String userName,
    required String password,
    bool requireCredentialsForAutoLogin = false,
    bool reportBlockedState = false,
    bool probeFnConnectOauth = false,
  }) {
    final bridge = jsonEncode(bridgeName);
    final user = jsonEncode(userName);
    final pass = jsonEncode(password);
    final credentialGuard = requireCredentialsForAutoLogin
        ? 'if (!AUTO_USER && !AUTO_PASS) return;'
        : '';
    final blockedProbe = reportBlockedState
        ? '''
      payload.title = String(document.title || '');
      const bodyText = (document.body && document.body.innerText) || '';
      payload.blocked =
        payload.title.indexOf('FN Connect') !== -1 ||
        bodyText.indexOf('\\u6682\\u65e0\\u6743\\u9650') !== -1;
'''
        : '';
    final oauthProbe = probeFnConnectOauth
        ? '''

  function installXhrHook() {
    if (window.__flyFnConnectXhrInstalled) return;
    window.__flyFnConnectXhrInstalled = true;

    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__fly_url = url;
      return originalOpen.apply(this, arguments);
    };

    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function(body) {
      const self = this;
      const originalReadyStateChange = self.onreadystatechange;
      self.onreadystatechange = function() {
        if (self.readyState === 4) {
          const url = String(self.__fly_url || '');
          if (url.indexOf('/oauthapi/authorize') !== -1) {
            let code = '';
            try {
              const json = JSON.parse(self.responseText || '{}');
              code = String(json && json.data ? json.data.code || '' : '');
            } catch (_) {}
            post({
              type: 'Response',
              url: url,
              code: code,
              body: self.responseText || ''
            });
          }
        }
        if (originalReadyStateChange) {
          originalReadyStateChange.apply(this, arguments);
        }
      };

      const url = String(this.__fly_url || '');
      if (url.indexOf('/sac/rpcproxy/v1/new-user-guide/status') !== -1) {
        post({ type: 'XHR', url: url });
      }
      return originalSend.apply(this, arguments);
    };
  }

  function installFetchHook() {
    if (window.__flyFnConnectFetchInstalled) return;
    window.__flyFnConnectFetchInstalled = true;

    const originalFetch = window.fetch;
    window.fetch = function(input, init) {
      let url = input;
      if (typeof input === 'object' && input && input.url) {
        url = input.url;
      }
      url = String(url || '');

      if (url.indexOf('/sac/rpcproxy/v1/new-user-guide/status') !== -1) {
        post({ type: 'XHR', url: url });
      }

      return originalFetch.apply(this, arguments).then((response) => {
        if (url.indexOf('/oauthapi/authorize') !== -1) {
          const clone = response.clone();
          clone.text().then((text) => {
            let code = '';
            try {
              const json = JSON.parse(text || '{}');
              code = String(json && json.data ? json.data.code || '' : '');
            } catch (_) {}
            post({ type: 'Response', url: url, code: code, body: text || '' });
          });
        }
        return response;
      });
    };
  }

  function fetchSysConfigOnce() {
    if (window.__flyFnConnectSysConfigRequested) return;
    if (window.location.href.indexOf('/login') !== -1) return;
    window.__flyFnConnectSysConfigRequested = true;
    fetch('/v/api/v1/sys/config', { credentials: 'include' })
      .then((response) => response.text())
      .then((text) => {
        post({
          type: 'SysConfig',
          url: '/v/api/v1/sys/config',
          body: text || ''
        });
        if (String(text || '').indexOf('nas_oauth') === -1) {
          window.__flyFnConnectSysConfigRequested = false;
        }
      })
      .catch(() => {
        window.__flyFnConnectSysConfigRequested = false;
      });
  }
'''
        : '';
    final oauthSetup = probeFnConnectOauth
        ? '''
  installXhrHook();
  installFetchHook();
  setTimeout(fetchSysConfigOnce, 800);
'''
        : '';
    final oauthTick = probeFnConnectOauth ? '    fetchSysConfigOnce();\n' : '';

    return '''
(() => {
  const BRIDGE = $bridge;
  const AUTO_USER = $user;
  const AUTO_PASS = $pass;

  function post(payload) {
    try {
      payload = payload || {};
      payload.cookie = document.cookie || '';
      payload.pageUrl = String(window.location.href || '');
$blockedProbe
      window[BRIDGE].postMessage(JSON.stringify(payload));
    } catch (_) {}
  }

  function triggerInput(input, value) {
    if (!input) return;
    const descriptor =
        Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
    if (descriptor && descriptor.set) {
      descriptor.set.call(input, value);
    } else {
      input.value = value;
    }
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
    input.dispatchEvent(new Event('blur', { bubbles: true }));
  }

  function normalizedText(element) {
    return String(
      (element && (
        element.innerText ||
        element.textContent ||
        element.placeholder ||
        element.name ||
        element.id ||
        element.autocomplete ||
        element.getAttribute && element.getAttribute('aria-label')
      )) || ''
    ).trim().toLowerCase();
  }

  function findInput(candidates, patterns) {
    for (let i = 0; i < candidates.length; i += 1) {
      const input = candidates[i];
      const text = normalizedText(input);
      for (let j = 0; j < patterns.length; j += 1) {
        if (text.indexOf(patterns[j]) !== -1) {
          return input;
        }
      }
    }
    return null;
  }

  function findText(elements, patterns) {
    for (let i = 0; i < elements.length; i += 1) {
      const text = normalizedText(elements[i]);
      for (let j = 0; j < patterns.length; j += 1) {
        if (text.indexOf(patterns[j].toLowerCase()) !== -1) {
          return elements[i];
        }
      }
    }
    return null;
  }

  function autoLogin() {
    $credentialGuard
    if (window.location.href.indexOf('/login') === -1) return;
    setTimeout(() => {
      const inputs = Array.from(document.querySelectorAll('input'));
      const userInput =
          document.querySelector('#username') ||
          document.querySelector('input[name="username"]') ||
          document.querySelector('input[autocomplete="username"]') ||
          findInput(inputs, ['username', 'user', 'account', 'login', '\\u7528\\u6237', '\\u8d26\\u53f7']) ||
          document.querySelector('input[type="text"]');
      const passInput =
          document.querySelector('#password') ||
          document.querySelector('input[name="password"]') ||
          document.querySelector('input[autocomplete="current-password"]') ||
          findInput(inputs, ['password', 'passwd', 'pass', '\\u5bc6\\u7801']) ||
          document.querySelector('input[type="password"]');
      if (userInput && AUTO_USER) {
        triggerInput(userInput, AUTO_USER);
      }
      if (passInput && AUTO_PASS) {
        triggerInput(passInput, AUTO_PASS);
      }
      setTimeout(() => {
        const submit =
            document.querySelector('button[type="submit"]') ||
            findText(
              document.querySelectorAll('button'),
              ['\\u767b\\u5f55', 'Login', 'Sign in', 'Sign In']
            );
        if (submit && !submit.disabled && submit.getAttribute('aria-disabled') !== 'true') {
          submit.click();
        }
      }, 250);
    }, 250);
  }

  function autoAuthorize() {
    if (window.location.href.indexOf('/signin') === -1 &&
        window.location.href.indexOf('/authorize') === -1 &&
        window.location.href.indexOf('/oauth') === -1) return;
    setTimeout(() => {
      const button = findText(
        document.querySelectorAll('button'),
        ['\\u6388\\u6743', '\\u540c\\u610f', 'Authorize', 'Agree', 'Continue', 'Allow']
      );
      if (button && !button.disabled && button.getAttribute('aria-disabled') !== 'true') {
        button.click();
      }
    }, 250);
  }

  function reportCookie() { post({ type: 'cookie' }); }
$oauthProbe

$oauthSetup
  autoLogin();
  autoAuthorize();
  reportCookie();
  let ticks = 0;
  const timer = setInterval(() => {
    ticks += 1;
    autoLogin();
    autoAuthorize();
$oauthTick    reportCookie();
    if (ticks >= 240) clearInterval(timer);
  }, 750);
})();
''';
  }
}
