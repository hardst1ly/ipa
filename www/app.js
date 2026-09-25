'use strict';

/* ================= Константы ================= */

const DAYS = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];
const SHORT = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
const DAYS_IN = ['понедельник', 'вторник', 'среду', 'четверг', 'пятницу', 'субботу'];
const STORAGE_KEY = 'schedule.v1';

// Стандартное расписание звонков (минуты от полуночи)
const BELLS = [
  [8 * 60 + 30, 9 * 60 + 15],
  [9 * 60 + 25, 10 * 60 + 10],
  [10 * 60 + 30, 11 * 60 + 15],
  [11 * 60 + 35, 12 * 60 + 20],
  [12 * 60 + 30, 13 * 60 + 15],
  [13 * 60 + 25, 14 * 60 + 10],
  [14 * 60 + 20, 15 * 60 + 5],
];

const SAMPLE_PLAN = [
  ['Математика', 'Русский язык', 'Литература', 'Английский язык', 'Физика', 'Физкультура'],
  ['Алгебра', 'История', 'Биология', 'Русский язык', 'Информатика', 'География'],
  ['Геометрия', 'Химия', 'Английский язык', 'Литература', 'Обществознание', 'Физкультура'],
  ['Алгебра', 'Физика', 'Русский язык', 'История', 'Биология', 'Технология'],
  ['Геометрия', 'Английский язык', 'Химия', 'Литература', 'Информатика'],
  ['Математика', 'География', 'Музыка', 'Физкультура'],
];

const SAMPLE_ROOMS = {
  'Математика': '21', 'Алгебра': '21', 'Геометрия': '21',
  'Русский язык': '14', 'Литература': '14',
  'Английский язык': '32', 'Физика': '25', 'Химия': '27',
  'Биология': '18', 'История': '11', 'Обществознание': '11',
  'География': '16', 'Информатика': '30', 'Физкультура': 'Спортзал',
  'Технология': '5', 'Музыка': '8',
};

/* ================= Утилиты ================= */

const $ = (sel) => document.querySelector(sel);

function uid() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

function fmt(min) {
  const h = Math.floor(min / 60), m = min % 60;
  return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0');
}

function parseTime(str) {
  const m = /^(\d{1,2}):(\d{2})/.exec(str || '');
  if (!m) return NaN;
  return Number(m[1]) * 60 + Number(m[2]);
}

function nowMinutes() {
  const d = new Date();
  return d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60;
}

/** 0 = Пн … 5 = Сб, null = воскресенье */
function todayIndex() {
  const wd = new Date().getDay(); // 0 = Вс
  return wd === 0 ? null : wd - 1;
}

function plural(n, one, few, many) {
  const m10 = n % 10, m100 = n % 100;
  if (m10 === 1 && m100 !== 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

function lessonsWord(n) { return plural(n, 'урок', 'урока', 'уроков'); }

function duration(min) {
  min = Math.max(0, Math.ceil(min));
  if (min >= 60) {
    const h = Math.floor(min / 60), m = min % 60;
    return m ? `${h} ч ${m} мин` : `${h} ч`;
  }
  return `${min} мин`;
}

function hueFor(text) {
  let h = 0;
  for (const ch of text) h = (h * 31 + ch.codePointAt(0)) >>> 0;
  return h % 360;
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === 'class') node.className = v;
    else if (k === 'style') node.style.cssText = v;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    node.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return node;
}

/* ================= Данные ================= */

function sample() {
  return SAMPLE_PLAN.map((list) =>
    list.map((subject, i) => ({
      id: uid(),
      subject,
      start: BELLS[i][0],
      end: BELLS[i][1],
      room: SAMPLE_ROOMS[subject] || '',
      teacher: '',
    })));
}

function sanitize(data) {
  if (!Array.isArray(data) || data.length !== 6 || !data.every(Array.isArray)) return null;
  return data.map((list) => list
    .filter((l) => l && typeof l.subject === 'string' && l.subject.trim() &&
      Number.isFinite(l.start) && Number.isFinite(l.end) && l.end > l.start)
    .map((l) => ({
      id: String(l.id || uid()),
      subject: l.subject.trim().slice(0, 60),
      start: Math.max(0, Math.min(1439, Math.round(l.start))),
      end: Math.max(0, Math.min(1439, Math.round(l.end))),
      room: String(l.room || '').slice(0, 30),
      teacher: String(l.teacher || '').slice(0, 60),
    }))
    .sort((a, b) => a.start - b.start));
}

function load() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      const days = sanitize(parsed && parsed.days ? parsed.days : parsed);
      if (days) return days;
    }
  } catch (e) { /* ignore */ }
  return sample();
}

function save() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ version: 1, days }));
  } catch (e) {
    toast('Не удалось сохранить 😕');
  }
}

let days = load();
let selected = todayIndex() ?? 0;

function sortDay(d) { days[d].sort((a, b) => a.start - b.start); }

function allSubjects() {
  return [...new Set(days.flat().map((l) => l.subject))].sort((a, b) => a.localeCompare(b, 'ru'));
}

function suggestTimes(d) {
  const list = days[d];
  const last = list[list.length - 1];
  const bell = BELLS[list.length];
  if (bell && (!last || last.end <= bell[0])) return bell;
  const start = Math.min((last ? last.end : BELLS[0][0]) + 10, 23 * 60);
  return [start, Math.min(start + 45, 1439)];
}

/* ================= Состояние «сейчас» ================= */

function lessonState(d, lesson) {
  if (d !== todayIndex()) return 'normal';
  const now = nowMinutes();
  if (lesson.start <= now && now < lesson.end) return 'current';
  if (lesson.end <= now) return 'past';
  const list = days[d];
  const hasCurrent = list.some((l) => l.start <= now && now < l.end);
  const next = list.find((l) => l.start > now);
  if (!hasCurrent && next && next.id === lesson.id) return 'next';
  return 'normal';
}

/* ================= Рендер ================= */

const wideQuery = window.matchMedia('(min-width: 900px)');

function render() {
  renderHeader();
  renderStatus();
  renderTabs();
  renderContent();
}

function renderHeader() {
  $('#today-date').textContent = new Date().toLocaleDateString('ru-RU', {
    weekday: 'long', day: 'numeric', month: 'long',
  });
}

function renderStatus() {
  const box = $('#status');
  box.replaceChildren();
  const t = todayIndex();
  const now = nowMinutes();

  const set = (label, main, sub, progress) => {
    box.append(el('div', { class: 'status-label' }, label));
    box.append(el('div', { class: 'status-main' }, main));
    if (sub) box.append(el('div', { class: 'status-sub' }, sub));
    if (progress != null) {
      box.append(el('div', { class: 'status-progress' },
        el('span', { style: `width:${Math.round(progress * 100)}%` })));
    }
  };

  const nextSchoolDay = () => {
    for (let i = 1; i <= 7; i++) {
      const idx = ((t ?? -1) + i) % 7;
      if (idx < 6 && days[idx].length) return idx;
    }
    return null;
  };

  const tomorrowText = () => {
    const nd = nextSchoolDay();
    if (nd == null) return 'Расписание пустое — добавьте уроки';
    const first = days[nd][0];
    const n = days[nd].length;
    return `${DAYS[nd]}: ${n} ${lessonsWord(n)}, начало в ${fmt(first.start)}`;
  };

  if (t == null) {
    set('Сегодня воскресенье', 'Выходной 🎉', tomorrowText());
    return;
  }
  const list = days[t];
  if (!list.length) {
    set('Сегодня', 'Уроков нет 🎉', tomorrowText());
    return;
  }
  const current = list.find((l) => l.start <= now && now < l.end);
  if (current) {
    const idx = list.indexOf(current);
    const p = (now - current.start) / (current.end - current.start);
    const next = list[idx + 1];
    const sub = `До конца ${duration(current.end - now)}` +
      (current.room ? ` · каб. ${current.room}` : '') +
      (next ? ` · далее ${next.subject}` : ' · это последний урок');
    set(`Сейчас · ${idx + 1}-й урок`, current.subject, sub, p);
    return;
  }
  const next = list.find((l) => l.start > now);
  if (next) {
    const idx = list.indexOf(next);
    if (now < list[0].start) {
      set('Первый урок', next.subject,
        `В ${fmt(next.start)} (через ${duration(next.start - now)})` + (next.room ? ` · каб. ${next.room}` : ''));
    } else {
      const prev = list[idx - 1];
      const p = prev ? (now - prev.end) / (next.start - prev.end) : null;
      set('Перемена', `Далее: ${next.subject}`,
        `В ${fmt(next.start)} (через ${duration(next.start - now)})` + (next.room ? ` · каб. ${next.room}` : ''), p);
    }
    return;
  }
  set('Сегодня', 'Уроки закончились 🎉', tomorrowText());
}

function renderTabs() {
  const tabs = $('#tabs');
  tabs.replaceChildren();
  const t = todayIndex();
  SHORT.forEach((name, i) => {
    tabs.append(el('button', {
      class: 'tab' + (i === selected ? ' active' : '') + (i === t ? ' today' : ''),
      role: 'tab',
      'aria-selected': String(i === selected),
      title: DAYS[i],
      onclick: () => { selected = i; render(); },
    }, name, el('span', { class: 'dot' })));
  });
}

function renderContent() {
  const content = $('#content');
  content.replaceChildren();
  const week = wideQuery.matches;
  content.classList.toggle('week', week);
  if (week) {
    DAYS.forEach((_, d) => content.append(renderDay(d, true)));
  } else {
    content.append(renderDay(selected, false));
  }
}

function renderDay(d, showEmptyCompact) {
  const list = days[d];
  const isToday = d === todayIndex();
  const wrap = el('section', { class: 'day' });

  const summary = list.length
    ? `${list.length} ${lessonsWord(list.length)} · ${fmt(list[0].start)}–${fmt(list[list.length - 1].end)}`
    : '';
  wrap.append(el('div', { class: 'day-header' },
    el('div', { class: 'day-title' }, DAYS[d], isToday ? el('span', { class: 'today-mark' }, ' · сегодня') : null),
    el('div', { class: 'day-summary' }, summary)));

  if (!list.length) {
    wrap.append(el('div', { class: 'empty' },
      el('div', { class: 'big' }, '📭'),
      el('div', {}, 'Уроков нет'),
      showEmptyCompact ? null : el('button', { class: 'btn secondary', onclick: () => openEditor(d, null) }, '+ Добавить урок')));
    return wrap;
  }

  const box = el('div', { class: 'lessons' });
  const now = nowMinutes();
  list.forEach((lesson, i) => {
    const prev = list[i - 1];
    if (prev && lesson.start > prev.end) {
      const breakNow = isToday && now >= prev.end && now < lesson.start;
      box.append(el('div', { class: 'break' + (breakNow ? ' now' : '') },
        `Перемена ${duration(lesson.start - prev.end)}` + (breakNow ? ' · сейчас' : '')));
    }
    box.append(renderLesson(d, lesson, i));
  });
  wrap.append(box);
  return wrap;
}

function renderLesson(d, lesson, i) {
  const state = lessonState(d, lesson);
  const meta = [el('span', { class: 'time' }, `${fmt(lesson.start)} – ${fmt(lesson.end)}`)];
  if (lesson.room) meta.push(' · ' + (/^\d+[а-яa-z]?$/i.test(lesson.room) ? `каб. ${lesson.room}` : lesson.room));
  if (lesson.teacher) meta.push(' · ' + lesson.teacher);

  let progress = null;
  if (state === 'current') {
    const p = (nowMinutes() - lesson.start) / (lesson.end - lesson.start);
    progress = el('div', { class: 'progress' }, el('span', { style: `width:${Math.round(p * 100)}%` }));
  }
  const badge = state === 'current' ? 'Сейчас' : state === 'next' ? 'Далее' : null;

  return el('button', {
    class: `lesson ${state}`,
    style: `--hue:${hueFor(lesson.subject)}`,
    onclick: () => openEditor(d, lesson),
  },
  el('div', { class: 'num' }, String(i + 1)),
  el('div', { class: 'body' },
    el('div', { class: 'subject' }, lesson.subject),
    el('div', { class: 'meta' }, meta),
    progress),
  badge ? el('span', { class: 'badge' }, badge) : null);
}

/* ================= Шторки (модальные окна) ================= */

const openSheets = [];

function openSheet(sheet) {
  $('#overlay').classList.remove('hidden');
  sheet.classList.remove('hidden');
  openSheets.push(sheet);
  // Чтобы кнопка «Назад» на Android закрывала окно, а не приложение
  history.pushState({ sheet: openSheets.length }, '');
}

function hideTopSheet() {
  const sheet = openSheets.pop();
  if (sheet) {
    sheet.classList.add('hidden');
    if (sheet._onClose) { const cb = sheet._onClose; sheet._onClose = null; cb(); }
  }
  if (!openSheets.length) $('#overlay').classList.add('hidden');
}

function closeSheet() {
  if (!openSheets.length) return;
  if (history.state && history.state.sheet) history.back(); // popstate закроет окно
  else hideTopSheet();
}

function closeAllSheets() {
  return new Promise((resolve) => {
    const step = () => {
      if (!openSheets.length) return resolve();
      closeSheet();
      setTimeout(step, 30);
    };
    step();
  });
}

window.addEventListener('popstate', () => {
  if (openSheets.length) hideTopSheet();
});

$('#overlay').addEventListener('click', closeSheet);
document.addEventListener('click', (e) => {
  if (e.target.closest('[data-close]')) closeSheet();
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && openSheets.length) closeSheet();
});

function confirmDialog(title, text, okLabel = 'OK', danger = false) {
  return new Promise((resolve) => {
    const sheet = $('#sheet-confirm');
    $('#confirm-title').textContent = title;
    $('#confirm-text').textContent = text;
    const ok = $('#confirm-ok');
    ok.textContent = okLabel;
    ok.className = 'btn ' + (danger ? 'danger' : 'primary');
    let result = false;
    sheet._onClose = () => resolve(result);
    ok.onclick = () => { result = true; closeSheet(); };
    $('#confirm-cancel').onclick = () => closeSheet();
    openSheet(sheet);
  });
}

let toastTimer = null;
function toast(text) {
  const t = $('#toast');
  t.textContent = text;
  t.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.add('hidden'), 2200);
}

/* ================= Редактор урока ================= */

let editing = null; // { day, id | null }

function openEditor(d, lesson) {
  editing = { day: d, id: lesson ? lesson.id : null };
  $('#editor-title').textContent = lesson ? 'Урок' : 'Новый урок';
  const [s, e] = lesson ? [lesson.start, lesson.end] : suggestTimes(d);
  $('#f-subject').value = lesson ? lesson.subject : '';
  $('#f-start').value = fmt(s);
  $('#f-end').value = fmt(e);
  $('#f-room').value = lesson ? lesson.room : '';
  $('#f-teacher').value = lesson ? lesson.teacher : '';
  $('#f-day').replaceChildren(...DAYS.map((name, i) => el('option', { value: i, selected: i === d }, name)));
  $('#subjects').replaceChildren(...allSubjects().map((s) => el('option', { value: s })));
  $('#btn-delete').classList.toggle('hidden', !lesson);
  $('#editor-error').classList.add('hidden');
  lastStart = s;
  openSheet($('#sheet-editor'));
  if (!lesson && !('ontouchstart' in window)) setTimeout(() => $('#f-subject').focus(), 250);
}

let lastStart = 0;

// При смене начала сдвигаем конец, сохраняя длительность урока
$('#f-start').addEventListener('change', () => {
  const ns = parseTime($('#f-start').value);
  const ce = parseTime($('#f-end').value);
  if (Number.isFinite(ns) && Number.isFinite(ce) && ce > lastStart) {
    $('#f-end').value = fmt(Math.min(ns + (ce - lastStart), 1439));
  }
  if (Number.isFinite(ns)) lastStart = ns;
});

// Выбрали предмет из подсказок — подставим кабинет и учителя
$('#f-subject').addEventListener('change', () => {
  const name = $('#f-subject').value.trim();
  const other = days.flat().find((l) => l.subject === name);
  if (!other) return;
  if (!$('#f-room').value) $('#f-room').value = other.room;
  if (!$('#f-teacher').value) $('#f-teacher').value = other.teacher;
});

function showEditorError(text) {
  const err = $('#editor-error');
  err.textContent = text;
  err.classList.remove('hidden');
}

$('#sheet-editor').addEventListener('submit', (e) => {
  e.preventDefault();
  const subject = $('#f-subject').value.trim();
  const start = parseTime($('#f-start').value);
  const end = parseTime($('#f-end').value);
  const targetDay = Number($('#f-day').value);
  if (!subject) return showEditorError('Введите название предмета');
  if (!Number.isFinite(start) || !Number.isFinite(end)) return showEditorError('Укажите время начала и конца');
  if (end <= start) return showEditorError('Урок должен заканчиваться позже, чем начинается');

  const data = {
    subject,
    start,
    end,
    room: $('#f-room').value.trim(),
    teacher: $('#f-teacher').value.trim(),
  };
  const { day, id } = editing;
  if (id) {
    const idx = days[day].findIndex((l) => l.id === id);
    if (idx >= 0) {
      const updated = { ...days[day][idx], ...data };
      if (targetDay !== day) {
        days[day].splice(idx, 1);
        days[targetDay].push(updated);
      } else {
        days[day][idx] = updated;
      }
    }
  } else {
    days[targetDay].push({ id: uid(), ...data });
  }
  sortDay(targetDay);
  save();
  closeSheet();
  if (!wideQuery.matches) selected = targetDay;
  render();
  toast(id ? 'Сохранено' : 'Урок добавлен');
});

$('#btn-delete').addEventListener('click', async () => {
  const { day, id } = editing;
  const lesson = days[day].find((l) => l.id === id);
  if (!lesson) return;
  const ok = await confirmDialog('Удалить урок?', `${lesson.subject}, ${fmt(lesson.start)}–${fmt(lesson.end)}`, 'Удалить', true);
  if (!ok) return;
  days[day] = days[day].filter((l) => l.id !== id);
  save();
  closeSheet();
  render();
  toast('Урок удалён');
});

/* ================= Меню ================= */

$('#btn-menu').addEventListener('click', () => openSheet($('#sheet-menu')));
$('#fab').addEventListener('click', () => openEditor(selected, null));

$('#sheet-menu').addEventListener('click', async (e) => {
  const btn = e.target.closest('[data-action]');
  if (!btn) return;
  const action = btn.dataset.action;
  await closeAllSheets();

  switch (action) {
    case 'today': {
      const t = todayIndex();
      if (t == null) { toast('Сегодня воскресенье — уроков нет 🙂'); break; }
      selected = t;
      render();
      break;
    }
    case 'copy': openCopy(); break;
    case 'export': openExport(); break;
    case 'import': openImport(); break;
    case 'reset': {
      const ok = await confirmDialog('Восстановить пример?', 'Всё текущее расписание будет заменено примером.', 'Восстановить', true);
      if (ok) { days = sample(); save(); render(); toast('Пример восстановлен'); }
      break;
    }
    case 'clear': {
      const ok = await confirmDialog(`Очистить ${DAYS_IN[selected]}?`, 'Все уроки этого дня будут удалены.', 'Очистить', true);
      if (ok) { days[selected] = []; save(); render(); toast('День очищен'); }
      break;
    }
    default: break;
  }
});

function openCopy() {
  const from = selected;
  $('#copy-title').textContent = `Скопировать ${DAYS_IN[from]} в…`;
  const box = $('#copy-days');
  box.replaceChildren(...DAYS.map((name, i) => i === from ? null : el('button', {
    onclick: async () => {
      await closeAllSheets();
      const ok = await confirmDialog(`Скопировать в ${DAYS_IN[i]}?`,
        `Уроки на ${DAYS_IN[i]} будут заменены уроками за ${DAYS_IN[from]}.`, 'Скопировать');
      if (!ok) return;
      days[i] = days[from].map((l) => ({ ...l, id: uid() }));
      save();
      selected = i;
      render();
      toast('Скопировано');
    },
  }, name)).filter(Boolean));
  openSheet($('#sheet-copy'));
}

function openExport() {
  $('#io-title').textContent = 'Экспорт расписания';
  $('#io-hint').textContent = 'Скопируйте этот текст и вставьте через «Импорт» на другом устройстве — телефоне или компьютере.';
  const text = $('#io-text');
  text.value = JSON.stringify({ version: 1, days });
  text.readOnly = true;
  const btn = $('#io-action');
  btn.textContent = 'Копировать';
  btn.onclick = async () => {
    try {
      await navigator.clipboard.writeText(text.value);
      toast('Скопировано в буфер обмена');
    } catch (e) {
      text.focus();
      text.select();
      const ok = document.execCommand && document.execCommand('copy');
      toast(ok ? 'Скопировано в буфер обмена' : 'Выделите текст и скопируйте вручную');
    }
  };
  openSheet($('#sheet-io'));
}

function openImport() {
  $('#io-title').textContent = 'Импорт расписания';
  $('#io-hint').textContent = 'Вставьте текст, полученный через «Экспорт». Текущее расписание будет заменено.';
  const text = $('#io-text');
  text.value = '';
  text.readOnly = false;
  const btn = $('#io-action');
  btn.textContent = 'Загрузить';
  btn.onclick = async () => {
    let parsed = null;
    try {
      const raw = JSON.parse(text.value.trim());
      parsed = sanitize(raw && raw.days ? raw.days : raw);
    } catch (e) { /* ignore */ }
    if (!parsed) { toast('Не получилось прочитать расписание'); return; }
    days = parsed;
    save();
    await closeAllSheets();
    render();
    toast('Расписание загружено');
  };
  openSheet($('#sheet-io'));
  setTimeout(() => text.focus(), 250);
}

/* ================= Запуск ================= */

// Чтобы «Назад» на Android при закрытых окнах просто выходил из приложения,
// начальное состояние истории — без флага окна.
history.replaceState({}, '');

wideQuery.addEventListener('change', render);
document.addEventListener('visibilitychange', () => { if (!document.hidden) render(); });

let lastDay = new Date().getDate();
setInterval(() => {
  if (openSheets.length) { renderStatus(); return; }
  // Наступил новый день — переключимся на него
  if (new Date().getDate() !== lastDay) {
    lastDay = new Date().getDate();
    selected = todayIndex() ?? selected;
  }
  render();
}, 30000);

render();
