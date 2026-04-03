export function fetchWithRetry(url, opts, cfg) {
  const retries   = (cfg && cfg.retries)   || 3;
  const baseDelay = (cfg && cfg.baseDelay) || 1000;
  function attempt(n) {
    return fetch(url, opts).then(function (res) {
      if (res.status >= 500 && n < retries) {
        return new Promise(function (resolve) {
          setTimeout(resolve, baseDelay * Math.pow(2, n));
        }).then(function () { return attempt(n + 1); });
      }
      return res;
    }).catch(function (err) {
      if (n < retries) {
        return new Promise(function (resolve) {
          setTimeout(resolve, baseDelay * Math.pow(2, n));
        }).then(function () { return attempt(n + 1); });
      }
      throw err;
    });
  }
  return attempt(0);
}

export function withButtonSpinner(btn, asyncFn) {
  if (!btn) return asyncFn();
  const original = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>';
  return asyncFn().finally(function () {
    btn.innerHTML = original;
    btn.disabled = false;
  });
}
