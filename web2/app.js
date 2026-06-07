// ════════════════════════════════════════════════════
//  MIRU ADMIN — app.js
//  Firebase Modular SDK (v10)
// ════════════════════════════════════════════════════

import { initializeApp }                    from 'https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js';
import { getAuth, GoogleAuthProvider,
         signInWithPopup, signOut,
         onAuthStateChanged }               from 'https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js';
import { getFirestore, collection, doc,
         getDoc, getDocs, setDoc,
         updateDoc, deleteDoc,
         query, orderBy, limit,
         onSnapshot, serverTimestamp,
         getCountFromServer }               from 'https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore.js';

// ── Firebase config ──────────────────────────────────
import { firebaseConfig } from './firebase-config.js';

const app  = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db   = getFirestore(app);

// ── Pages ─────────────────────────────────────────────
const pages = {
  login:     document.getElementById('page-login'),
  denied:    document.getElementById('page-denied'),
  loading:   document.getElementById('page-loading'),
  dashboard: document.getElementById('page-dashboard'),
};

function showPage(name) {
  Object.values(pages).forEach(p => p.classList.remove('active'));
  pages[name].classList.add('active');
}

// ── Toast ─────────────────────────────────────────────
const toast = document.getElementById('toast');
let toastTimer;

function showToast(msg, type = 'info') {
  clearTimeout(toastTimer);
  toast.textContent = msg;
  toast.className = `toast ${type} show`;
  toastTimer = setTimeout(() => { toast.classList.remove('show'); }, 3500);
}

// ── Confirm modal ─────────────────────────────────────
const modalOverlay = document.getElementById('modal-overlay');

function showConfirm(title, body) {
  return new Promise(resolve => {
    document.getElementById('modal-title').textContent = title;
    document.getElementById('modal-body').textContent  = body;
    modalOverlay.classList.remove('hidden');

    const confirm = document.getElementById('modal-confirm');
    const cancel  = document.getElementById('modal-cancel');

    const cleanup = (val) => {
      modalOverlay.classList.add('hidden');
      confirm.removeEventListener('click', onConfirm);
      cancel.removeEventListener('click',  onCancel);
      resolve(val);
    };
    const onConfirm = () => cleanup(true);
    const onCancel  = () => cleanup(false);
    confirm.addEventListener('click', onConfirm);
    cancel.addEventListener('click',  onCancel);
  });
}

// ── Auth ──────────────────────────────────────────────
document.getElementById('btn-google-login').addEventListener('click', async () => {
  try {
    const provider = new GoogleAuthProvider();
    await signInWithPopup(auth, provider);
  } catch (e) {
    if (e.code === 'auth/popup-closed-by-user') return; // user closed it
    showToast('Error al iniciar sesión: ' + e.message, 'error');
    console.error('signInWithPopup error:', e);
  }
});

document.getElementById('btn-logout').addEventListener('click', () => signOut(auth));
document.getElementById('btn-logout-denied').addEventListener('click', () => signOut(auth));

async function isAdmin(uid) {
  try {
    const snap = await getDoc(doc(db, 'admins', uid));
    return snap.exists();
  } catch (e) {
    console.warn('isAdmin read failed:', e.message);
    return false;
  }
}

let _dataLoaded = false;

onAuthStateChanged(auth, async (user) => {
  // Firebase resolves auth state asynchronously on load.
  // The page starts on 'loading', so there's no login flash.
  if (!user) { showPage('login'); _dataLoaded = false; return; }

  showPage('loading');

  let admin = false;
  try {
    admin = await isAdmin(user.uid);
  } catch (e) {
    // Permissions error — likely no admin doc yet
    console.warn('isAdmin check failed:', e.message);
  }

  if (!admin) {
    // Update denied page with helpful info
    const deniedEl = document.getElementById('page-denied');
    const msg = deniedEl.querySelector('p');
    if (msg) {
      msg.innerHTML =
        'Tu cuenta (<b>' + (user.email || user.uid) + '</b>) no tiene permisos de admin.<br><br>' +
        'Si aún no creaste el primer admin, ve a: ' +
        '<a href="/setup-admin.html" style="color:var(--primary)">setup-admin.html</a>';
    }
    showPage('denied');
    return;
  }

  // Set sidebar user info
  const avatar = document.getElementById('admin-avatar');
  if (user.photoURL) { avatar.src = user.photoURL; }
  else               { avatar.style.display = 'none'; }
  document.getElementById('admin-name').textContent = user.displayName || user.email;

  showPage('dashboard');
  if (!_dataLoaded) { _dataLoaded = true; loadAllData(); }
});

// ── Navigation ────────────────────────────────────────
const navItems   = document.querySelectorAll('.nav-item');
const topbarTitle = document.getElementById('topbar-title');
const sectionTitles = {
  'section-overview':   'Resumen',
  'section-users':      'Usuarios',
  'section-chat':       'Chat público',
  'section-supporters': 'Supporters',
  'section-admins':     'Administradores',
};

navItems.forEach(item => {
  item.addEventListener('click', () => {
    navItems.forEach(n => n.classList.remove('active'));
    item.classList.add('active');
    const id = item.dataset.section;
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    document.getElementById(id).classList.add('active');
    topbarTitle.textContent = sectionTitles[id] || '';
    closeSidebar();
  });
});

// Mobile sidebar toggle
const sidebarEl = document.getElementById('sidebar');
document.getElementById('sidebar-toggle').addEventListener('click', () => {
  sidebarEl.classList.toggle('open');
});
function closeSidebar() { sidebarEl.classList.remove('open'); }

// ── Data loaders ──────────────────────────────────────
function loadAllData() {
  loadOverview();
  loadUsers();
  loadChat();
  loadSupporters();
  loadAdmins();
}

// ── OVERVIEW ─────────────────────────────────────────
async function loadOverview() {
  const safeCount = async (col) => {
    try { return (await getCountFromServer(col)).data().count; } catch (_) { return '—'; }
  };
  const [usersCount, chatCount] = await Promise.all([
    safeCount(collection(db, 'users')),
    safeCount(collection(db, 'public_chat')),
  ]);
  document.getElementById('stat-users').textContent    = usersCount;
  document.getElementById('stat-messages').textContent = chatCount;
  try {
    const allUsers = await getDocs(collection(db, 'users'));
    document.getElementById('stat-supporters').textContent =
      allUsers.docs.filter(d => d.data().isSupporter === true).length;
  } catch (_) { document.getElementById('stat-supporters').textContent = '—'; }
  try {
    const adminsSnap = await getDocs(collection(db, 'admins'));
    document.getElementById('stat-admins').textContent = adminsSnap.size;
  } catch (_) { document.getElementById('stat-admins').textContent = '—'; }

  // Recent chat messages
  const q = query(collection(db, 'public_chat'), orderBy('timestamp', 'desc'), limit(10));
  onSnapshot(q, snap => {
    const el = document.getElementById('recent-chat');
    if (snap.empty) { el.innerHTML = '<div class="loading-row">Sin mensajes aún.</div>'; return; }
    el.innerHTML = snap.docs.map(d => {
      const m = d.data();
      const time = m.timestamp?.toDate ? formatTime(m.timestamp.toDate()) : '';
      const sup  = m.isSupporter ? '👑 ' : '';
      return `
        <div class="recent-row">
          ${avatarHtml(m.userAvatar, m.userName, 30)}
          <div style="flex:1;min-width:0">
            <div style="font-size:12px;font-weight:600">${sup}${esc(m.userName)}</div>
            <div style="font-size:13px;word-break:break-word;margin-top:2px">${esc(m.text || (m.stickerCode ? '🎭 Sticker' : '📷 Imagen'))}</div>
          </div>
          <div style="font-size:11px;color:var(--text-secondary);flex-shrink:0">${time}</div>
        </div>`;
    }).join('');
  });
}

// ── USERS ─────────────────────────────────────────────
let allUsersCache = [];

async function loadUsers() {
  const tbody = document.getElementById('users-tbody');
  tbody.innerHTML = '<tr><td colspan="7" class="loading-cell">Cargando usuarios…</td></tr>';

  try {
    const snap = await getDocs(collection(db, 'users'));
    allUsersCache = snap.docs
      .map(d => ({ id: d.id, ...d.data() }))
      .sort((a, b) => {
        const ta = a.createdAt?.toMillis?.() ?? 0;
        const tb = b.createdAt?.toMillis?.() ?? 0;
        return tb - ta;
      });
    renderUsersTable(allUsersCache);
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="7" class="loading-cell" style="color:var(--danger)">Error: ${esc(e.message)}</td></tr>`;
  }
}

document.getElementById('user-search').addEventListener('input', e => {
  const q = e.target.value.toLowerCase();
  const filtered = allUsersCache.filter(u =>
    (u.displayName || '').toLowerCase().includes(q) ||
    (u.email       || '').toLowerCase().includes(q) ||
    (u.id          || '').toLowerCase().includes(q)
  );
  renderUsersTable(filtered);
});

function renderUsersTable(users) {
  const tbody = document.getElementById('users-tbody');
  if (!users.length) {
    tbody.innerHTML = '<tr><td colspan="7" class="loading-cell">Sin resultados.</td></tr>';
    return;
  }
  tbody.innerHTML = users.map(u => {
    const created = u.createdAt?.toDate ? formatDate(u.createdAt.toDate()) : '—';
    const profileBadge = u.isPublic === false
      ? '<span class="badge badge-private">Privado</span>'
      : '<span class="badge badge-public">Público</span>';
    const supBadge = u.isSupporter
      ? '<span class="badge badge-supporter">👑 Sí</span>'
      : '<span class="badge badge-no">No</span>';
    const adminBadge = u.isAdmin
      ? '<span class="badge badge-admin">✓ Admin</span>'
      : '<span class="badge badge-no">No</span>';
    return `
      <tr>
        <td>
          <div class="user-cell">
            ${avatarHtml(u.photoUrl, u.displayName, 34)}
            <div>
              <div class="user-name">${esc(u.displayName || 'Sin nombre')}</div>
              <div class="user-uid">${u.id}</div>
            </div>
          </div>
        </td>
        <td style="color:var(--text-secondary);font-size:12px">${esc(u.email || '—')}</td>
        <td>${profileBadge}</td>
        <td>${supBadge}</td>
        <td>${adminBadge}</td>
        <td style="color:var(--text-secondary);font-size:12px">${created}</td>
        <td>
          <div style="display:flex;gap:4px">
            <button class="btn-icon ${u.isSupporter ? 'danger' : 'success'}"
              title="${u.isSupporter ? 'Quitar supporter' : 'Hacer supporter'}"
              onclick="toggleSupporter('${u.id}', ${!!u.isSupporter})">
              ${u.isSupporter
                ? '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/><line x1="4" y1="4" x2="20" y2="20" stroke="var(--danger)" stroke-width="2"/></svg>'
                : '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>'
              }
            </button>
            <button class="btn-icon danger"
              title="Eliminar usuario del panel"
              onclick="deleteUserRecord('${u.id}', '${esc(u.displayName || u.id)}')">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/></svg>
            </button>
          </div>
        </td>
      </tr>`;
  }).join('');
}

window.toggleSupporter = async (uid, current) => {
  const action = current ? 'Quitar supporter a' : 'Hacer supporter a';
  const ok = await showConfirm(`${action} este usuario`, `UID: ${uid}`);
  if (!ok) return;
  try {
    await updateDoc(doc(db, 'users', uid), { isSupporter: !current });
    showToast(current ? 'Supporter removido' : 'Supporter activado ✓', 'success');
    loadUsers();
    loadOverview();
  } catch (e) { showToast(e.message, 'error'); }
};

window.deleteUserRecord = async (uid, name) => {
  const ok = await showConfirm('Eliminar registro de usuario', `Se eliminará el documento de Firestore de "${name}". Esta acción no borra la cuenta de Firebase Auth.`);
  if (!ok) return;
  try {
    await deleteDoc(doc(db, 'users', uid));
    showToast('Registro eliminado', 'success');
    loadUsers();
  } catch (e) { showToast(e.message, 'error'); }
};

// ── CHAT MODERATION ───────────────────────────────────
function loadChat() {
  const q = query(collection(db, 'public_chat'), orderBy('timestamp', 'desc'), limit(50));
  const el = document.getElementById('chat-list');
  el.innerHTML = '<div class="loading-row">Cargando…</div>';

  onSnapshot(q, snap => {
    if (snap.empty) { el.innerHTML = '<div class="loading-row">Sin mensajes.</div>'; return; }
    el.innerHTML = snap.docs.map(d => {
      const m = d.data();
      const time = m.timestamp?.toDate ? formatTime(m.timestamp.toDate()) : '';
      const sup  = m.isSupporter ? '<span class="badge badge-supporter" style="font-size:10px">👑</span> ' : '';
      const content = m.text
        ? `<div class="chat-row-text">${esc(m.text)}</div>`
        : m.stickerCode
          ? `<div class="chat-row-text" style="color:var(--text-secondary)">🎭 Sticker</div>`
          : m.fileUrl
            ? `<div class="chat-row-text" style="color:var(--text-secondary)">📷 Imagen</div>`
            : '';
      return `
        <div class="chat-row" id="msg-${d.id}">
          ${avatarHtml(m.userAvatar, m.userName, 32)}
          <div class="chat-row-body">
            <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap">
              ${sup}<span style="font-weight:600;font-size:12px">${esc(m.userName)}</span>
              <span class="chat-row-meta">${time}</span>
            </div>
            ${content}
          </div>
          <div class="chat-row-actions">
            <button class="btn-icon danger" title="Eliminar mensaje" onclick="deleteChatMsg('${d.id}')">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/></svg>
            </button>
          </div>
        </div>`;
    }).join('');
  });
}

document.getElementById('btn-refresh-chat').addEventListener('click', loadChat);

window.deleteChatMsg = async (id) => {
  const ok = await showConfirm('Eliminar mensaje', 'Esta acción no se puede deshacer.');
  if (!ok) return;
  try {
    await deleteDoc(doc(db, 'public_chat', id));
    showToast('Mensaje eliminado', 'success');
  } catch (e) { showToast(e.message, 'error'); }
};

// ── SUPPORTERS ────────────────────────────────────────
async function loadSupporters() {
  const tbody = document.getElementById('supporters-tbody');
  tbody.innerHTML = '<tr><td colspan="4" class="loading-cell">Cargando…</td></tr>';
  try {
    const snap = await getDocs(collection(db, 'users'));
    const supporters = snap.docs
      .filter(d => d.data().isSupporter === true)
      .map(d => ({ id: d.id, ...d.data() }));

    if (!supporters.length) {
      tbody.innerHTML = '<tr><td colspan="4" class="loading-cell">Sin supporters aún.</td></tr>';
      return;
    }
    tbody.innerHTML = supporters.map(u => {
      const since = u.supporterSince?.toDate ? formatDate(u.supporterSince.toDate()) : '—';
      return `
        <tr>
          <td><div class="user-cell">${avatarHtml(u.photoUrl, u.displayName, 32)}<div><div class="user-name">${esc(u.displayName || '—')}</div><div class="user-uid">${u.id}</div></div></div></td>
          <td style="font-size:12px;color:var(--text-secondary)">${esc(u.email || '—')}</td>
          <td style="font-size:12px;color:var(--text-secondary)">${since}</td>
          <td>
            <button class="btn-icon danger" title="Quitar supporter" onclick="toggleSupporter('${u.id}', true)">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
            </button>
          </td>
        </tr>`;
    }).join('');
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="4" class="loading-cell" style="color:var(--danger)">${esc(e.message)}</td></tr>`;
  }
}

document.getElementById('btn-add-supporter').addEventListener('click', async () => {
  let input = document.getElementById('supporter-uid-input').value.trim();
  if (!input) { showToast('Ingresa el UID o email del usuario', 'error'); return; }

  // If input looks like an email, search the users collection for it
  let uid = input;
  let displayInfo = input;
  if (input.includes('@')) {
    showToast('Buscando usuario…', 'info');
    try {
      const snap = await getDocs(collection(db, 'users'));
      const found = snap.docs.find(d => (d.data().email || '').toLowerCase() === input.toLowerCase());
      if (!found) { showToast('No se encontró ningún usuario con ese email', 'error'); return; }
      uid = found.id;
      displayInfo = `${found.data().displayName || uid} (${input})`;
    } catch (e) { showToast('Error buscando usuario: ' + e.message, 'error'); return; }
  }

  const ok = await showConfirm('Activar supporter', displayInfo);
  if (!ok) return;
  try {
    await updateDoc(doc(db, 'users', uid), {
      isSupporter:    true,
      supporterSince: serverTimestamp(),
    });
    showToast('Supporter activado ✓', 'success');
    document.getElementById('supporter-uid-input').value = '';
    loadSupporters();
    loadOverview();
  } catch (e) { showToast(e.message, 'error'); }
});

// ── ADMINS ────────────────────────────────────────────
async function loadAdmins() {
  const tbody = document.getElementById('admins-tbody');
  tbody.innerHTML = '<tr><td colspan="4" class="loading-cell">Cargando…</td></tr>';
  try {
    const snap = await getDocs(collection(db, 'admins'));
    if (snap.empty) {
      tbody.innerHTML = '<tr><td colspan="4" class="loading-cell">Sin admins registrados.</td></tr>';
      return;
    }
    // Fetch display names from users collection in parallel
    const rows = await Promise.all(snap.docs.map(async d => {
      const uid  = d.id;
      const data = d.data();
      let name = data.displayName || '—';
      let email = data.email || '—';
      let photo = data.photoUrl || null;
      try {
        const usnap = await getDoc(doc(db, 'users', uid));
        if (usnap.exists()) {
          const u = usnap.data();
          name  = u.displayName || name;
          email = u.email       || email;
          photo = u.photoUrl    || photo;
        }
      } catch (_) {}
      const since = data.addedAt?.toDate ? formatDate(data.addedAt.toDate()) : '—';
      return `
        <tr>
          <td><div class="user-cell">${avatarHtml(photo, name, 32)}<div><div class="user-name">${esc(name)}</div><div class="user-uid">${uid}</div></div></div></td>
          <td style="font-size:12px;color:var(--text-secondary)">${esc(email)}</td>
          <td style="font-size:12px;color:var(--text-secondary)">${since}</td>
          <td>
            <button class="btn-icon danger" title="Revocar admin" onclick="revokeAdmin('${uid}', '${esc(name)}')">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
            </button>
          </td>
        </tr>`;
    }));
    tbody.innerHTML = rows.join('');
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="4" class="loading-cell" style="color:var(--danger)">${esc(e.message)}</td></tr>`;
  }
}

document.getElementById('btn-add-admin').addEventListener('click', async () => {
  const uid = document.getElementById('admin-uid-input').value.trim();
  if (!uid) { showToast('Ingresa el UID del usuario', 'error'); return; }
  const ok = await showConfirm('Agregar admin', `Se dará acceso de administrador a UID: ${uid}`);
  if (!ok) return;
  try {
    // Fetch user display info
    let displayName = '', email = '', photoUrl = '';
    try {
      const usnap = await getDoc(doc(db, 'users', uid));
      if (usnap.exists()) {
        const u = usnap.data();
        displayName = u.displayName || '';
        email       = u.email       || '';
        photoUrl    = u.photoUrl    || '';
      }
    } catch (_) {}

    await setDoc(doc(db, 'admins', uid), {
      addedAt:     serverTimestamp(),
      addedBy:     auth.currentUser?.uid || '',
      displayName, email, photoUrl,
    });
    showToast('Admin agregado ✓', 'success');
    document.getElementById('admin-uid-input').value = '';
    loadAdmins();
  } catch (e) { showToast(e.message, 'error'); }
});

window.revokeAdmin = async (uid, name) => {
  if (uid === auth.currentUser?.uid) {
    showToast('No puedes revocarte a ti mismo', 'error'); return;
  }
  const ok = await showConfirm('Revocar admin', `Quitar acceso de admin a "${name}"?`);
  if (!ok) return;
  try {
    await deleteDoc(doc(db, 'admins', uid));
    showToast('Admin revocado', 'success');
    loadAdmins();
  } catch (e) { showToast(e.message, 'error'); }
};

// ── Helpers ───────────────────────────────────────────
function esc(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;');
}

function avatarHtml(url, name, size = 34) {
  const s = `width:${size}px;height:${size}px;border-radius:50%;object-fit:cover;flex-shrink:0`;
  if (url) return `<img src="${esc(url)}" alt="" style="${s};background:var(--surface2)" onerror="this.style.display='none'">`;
  const initial = (name || '?')[0].toUpperCase();
  return `<div style="${s};background:var(--primary);color:white;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:${Math.round(size*0.4)}px">${esc(initial)}</div>`;
}

function formatTime(date) {
  if (!(date instanceof Date)) return '';
  return date.toLocaleString('es', { day:'2-digit', month:'2-digit', year:'2-digit', hour:'2-digit', minute:'2-digit' });
}

function formatDate(date) {
  if (!(date instanceof Date)) return '';
  return date.toLocaleDateString('es', { day:'2-digit', month:'2-digit', year:'numeric' });
}
