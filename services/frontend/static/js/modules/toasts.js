import { escapeHtml } from './formatting.js';

export function showToast(message, type) {
  const box = document.getElementById('toast-box');
  if (!box) return;
  const id  = 'toast-' + Date.now();
  const cls = 'toast-' + (type || 'info');
  const html =
    '<div id="' + id + '" class="toast toast-glass ' + cls + '" role="alert" aria-live="assertive" aria-atomic="true" data-bs-delay="5000">' +
      '<div class="d-flex">' +
        '<div class="toast-body">' + escapeHtml(message) + '</div>' +
        '<button type="button" class="btn-close me-2 m-auto" data-bs-dismiss="toast" aria-label="Закрити"></button>' +
      '</div>' +
    '</div>';
  box.insertAdjacentHTML('beforeend', html);
  const el = document.getElementById(id);
  if (el && typeof bootstrap !== 'undefined' && bootstrap.Toast) {
    const t = new bootstrap.Toast(el);
    t.show();
    el.addEventListener('hidden.bs.toast', function () { el.remove(); });
  }
}
