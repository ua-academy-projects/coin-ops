export function createDropdownMenuItem(value, labelText, buttonClassName) {
  const li  = document.createElement('li');
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = buttonClassName || 'dropdown-item';
  btn.setAttribute('data-value', value);
  btn.textContent = labelText;
  li.appendChild(btn);
  return li;
}

export function fillHiddenSelectAndMenu(selectEl, menuEl, pairs) {
  selectEl.innerHTML = '';
  menuEl.innerHTML   = '';
  pairs.forEach(function (p) {
    selectEl.appendChild(new Option(p.label, p.value));
    menuEl.appendChild(createDropdownMenuItem(p.value, p.label));
  });
}

export function syncDropdownLabel(selectEl, labelEl) {
  if (!selectEl || !labelEl) return;
  const opt = selectEl.options[selectEl.selectedIndex];
  labelEl.textContent = opt ? opt.text : '—';
}

export function wireCoSelectDropdown(toggleBtn, menuEl, selectEl, onPick) {
  if (!toggleBtn || !menuEl || !selectEl) return;
  const labelSpan = toggleBtn.querySelector('[data-co-select-label]');
  menuEl.addEventListener('click', function (ev) {
    const item = ev.target.closest('button[data-value]');
    if (!item || !menuEl.contains(item)) return;
    ev.preventDefault();
    selectEl.value = item.getAttribute('data-value');
    syncDropdownLabel(selectEl, labelSpan);
    if (onPick) onPick();
    if (typeof bootstrap !== 'undefined' && bootstrap.Dropdown) {
      const inst = bootstrap.Dropdown.getInstance(toggleBtn);
      if (inst) inst.hide();
    }
  });
}

export function wireCoSelectTypeahead(toggleBtn, menuEl) {
  if (!toggleBtn || !menuEl) return;
  let handler = null;
  toggleBtn.addEventListener('shown.bs.dropdown', function () {
    handler = function (e) {
      if (e.key.length !== 1 || e.ctrlKey || e.metaKey || e.altKey) return;
      const ch = e.key.toLowerCase();
      const items = menuEl.querySelectorAll('button[data-value]');
      for (const node of items) {
        const t = (node.textContent || '').trim().toLowerCase();
        if (t.startsWith(ch)) {
          node.focus();
          node.scrollIntoView({ block: 'nearest' });
          e.preventDefault();
          break;
        }
      }
    };
    document.addEventListener('keydown', handler, true);
  });
  toggleBtn.addEventListener('hidden.bs.dropdown', function () {
    if (handler) {
      document.removeEventListener('keydown', handler, true);
      handler = null;
    }
  });
}
