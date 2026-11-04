const DEFAULT_DRIVE_KEY = 'AIzaSyAJrwuxW1017I4rzQrf_xDXG63zKqpnLAA';

const menuButton = document.querySelector('.menu-toggle');
const nav = document.querySelector('.desktop-nav');
const header = document.querySelector('.site-header');

menuButton?.addEventListener('click', () => {
  const isOpen = menuButton.getAttribute('aria-expanded') === 'true';
  menuButton.setAttribute('aria-expanded', String(!isOpen));
  nav?.classList.toggle('nav-open', !isOpen);
});

nav?.querySelectorAll('a')?.forEach((link) => {
  link.addEventListener('click', () => {
    menuButton?.setAttribute('aria-expanded', 'false');
    nav.classList.remove('nav-open');
  });
});

document.addEventListener('scroll', () => {
  header?.classList.toggle('scrolled', window.scrollY > 8);
}, { passive: true });

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.12 });

document.querySelectorAll('.reveal').forEach((element) => observer.observe(element));
document.querySelector('#year').textContent = new Date().getFullYear();

const galleryFrameWrap = document.querySelector('#gallery-frame-wrap');
const galleryGrid = document.querySelector('#gallery-grid');
const galleryNote = document.querySelector('#gallery-note');
const galleryEmpty = document.querySelector('#gallery-empty');
const loadMoreBtn = document.querySelector('#load-more');
const selectToolbar = document.querySelector('#select-toolbar');
const selectCount = document.querySelector('#select-count');
const selectDownloadBtn = document.querySelector('#select-download');
const selectClearBtn = document.querySelector('#select-clear');
const selectPanel = document.querySelector('#select-panel');
const selectPanelCount = document.querySelector('#select-panel-count');
const selectPanelGrid = document.querySelector('#select-panel-grid');
const selectPanelClear = document.querySelector('#select-panel-clear');

const keyModal = document.querySelector('#key-modal');
const keyToggle = document.querySelector('#key-toggle');
const keyClose = document.querySelector('#key-close');
const keyInput = document.querySelector('#drive-api-key');
const keySave = document.querySelector('#key-save');
const keyNote = document.querySelector('#key-note');

const pinGate = document.querySelector('#pin-gate');
const pinInput = document.querySelector('#pin-input');
const pinSubmit = document.querySelector('#pin-submit');
const pinNote = document.querySelector('#pin-note');

const lightbox = document.querySelector('#lightbox');
const lightboxImg = document.querySelector('#lightbox-img');
const lightboxCaption = document.querySelector('#lightbox-caption');
const lightboxFav = document.querySelector('#lightbox-fav');
const lightboxClose = document.querySelector('#lightbox-close');
const lightboxPrev = document.querySelector('#lightbox-prev');
const lightboxNext = document.querySelector('#lightbox-next');

const params = new URLSearchParams(window.location.search);
const STORAGE_KEY = 'shortir_drive_key';
const REQUIRED_PIN = params.get('pin') || '';
const MAX_SELECTIONS = Number(params.get('max')) || Infinity;
const PIN_SESSION_KEY = `shortir_pin_${REQUIRED_PIN}`;

const galleryTitle = document.querySelector('#gallery-title');
const GALLERY_NAME = params.get('name') || '';
if (galleryTitle && GALLERY_NAME) galleryTitle.textContent = GALLERY_NAME;

const EXPIRY = params.get('until') ? new Date(`${params.get('until')}T23:59:59`) : null;
function isExpired() {
  return EXPIRY && Date.now() > EXPIRY.getTime();
}

let driveKey = params.get('key') || localStorage.getItem(STORAGE_KEY) || DEFAULT_DRIVE_KEY;
let currentFolderId = null;
let nextPageToken = null;
let currentImages = [];
const selectedIndices = new Set();

function getDriveFolderId(value) {
  try {
    const url = new URL(value);
    const match = url.pathname.match(/\/folders\/([^/]+)/);
    return match ? match[1] : url.searchParams.get('id');
  } catch (_) {
    return null;
  }
}

function setKeyText(k) {
  keyInput.value = k;
  keyNote.textContent = k ? 'API key tersimpan di browser ini.' : '';
  keyNote.classList.toggle('ok', Boolean(k));
}

keyToggle?.addEventListener('click', () => {
  keyModal.hidden = false;
  setKeyText(driveKey);
  keyInput.focus();
});

keyClose?.addEventListener('click', () => { keyModal.hidden = true; });
keyModal?.addEventListener('click', (event) => {
  if (event.target === keyModal) keyModal.hidden = true;
});

keySave?.addEventListener('click', () => {
  const value = keyInput.value.trim();
  driveKey = value;
  if (value) localStorage.setItem(STORAGE_KEY, value);
  else localStorage.removeItem(STORAGE_KEY);
  keyModal.hidden = true;
});

if (REQUIRED_PIN && sessionStorage.getItem(PIN_SESSION_KEY) !== 'ok') {
  pinGate.hidden = false;
  pinSubmit?.addEventListener('click', () => {
    if (pinInput.value.trim() === REQUIRED_PIN) {
      sessionStorage.setItem(PIN_SESSION_KEY, 'ok');
      pinGate.hidden = true;
      pinInput.value = '';
    } else {
      pinNote.textContent = 'PIN salah. Coba lagi.';
      pinInput.value = '';
      pinInput.focus();
    }
  });
  pinInput?.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') pinSubmit.click();
  });
}

function thumbnailUrl(id) {
  return `https://drive.google.com/thumbnail?id=${encodeURIComponent(id)}&sz=w2000`;
}

function renderSkeleton(count) {
  galleryGrid.innerHTML = '';
  for (let i = 0; i < count; i++) {
    const div = document.createElement('div');
    div.className = 'gallery-item skeleton';
    galleryGrid.appendChild(div);
  }
}

function formatNumber(index) {
  return String(index + 1).padStart(3, '0');
}

function fullImageUrl(item) {
  if (item.url) return item.url;
  if (item.id) {
    return `https://drive.google.com/uc?export=view&id=${encodeURIComponent(item.id)}`;
  }
  return '';
}

function openLightbox(index) {
  const item = currentImages[index];
  if (!item) return;
  const figure = document.querySelector('.lightbox-figure');
  if (figure) figure.classList.remove('zoomed');
  lightboxImg.src = fullImageUrl(item) || thumbnailUrl(item.id);
  lightboxImg.alt = item.name;
  lightboxImg.onerror = () => {
    if (item.id && lightboxImg.src !== thumbnailUrl(item.id)) {
      lightboxImg.onerror = null;
      lightboxImg.src = thumbnailUrl(item.id);
    }
  };
  lightboxCaption.textContent = `#${formatNumber(index)} · ${item.name}`;
  lightbox.dataset.index = String(index);
  lightbox.hidden = false;
  updateLightboxFav();
  document.body.style.overflow = 'hidden';
}

function toggleLightboxZoom() {
  const figure = document.querySelector('.lightbox-figure');
  if (!figure) return;
  figure.classList.toggle('zoomed');
}

function closeLightbox() {
  const figure = document.querySelector('.lightbox-figure');
  if (figure) figure.classList.remove('zoomed');
  lightbox.hidden = true;
  document.body.style.overflow = '';
}

function stepLightbox(step) {
  const index = (Number(lightbox.dataset.index) + step + currentImages.length) % currentImages.length;
  openLightbox(index);
}

galleryGrid?.addEventListener('click', (event) => {
  if (event.target.closest('.item-check') || event.target.closest('.item-download')) return;
  const item = event.target.closest('.gallery-item[data-index]');
  if (item) openLightbox(Number(item.dataset.index));
});

const promoGrid = document.querySelector('.gallery-promo-grid');
promoGrid?.addEventListener('click', (event) => {
  const cell = event.target.closest('.promo-cell');
  if (!cell) return;
  event.preventDefault();
  const cells = [...promoGrid.querySelectorAll('.promo-cell')];
  currentImages = cells.map((c) => ({
    id: null,
    name: c.dataset.name || 'Foto',
    url: c.dataset.img,
  }));
  selectedIndices.clear();
  openLightbox(cells.indexOf(cell));
});

lightboxClose?.addEventListener('click', closeLightbox);
lightboxPrev?.addEventListener('click', () => stepLightbox(-1));
lightboxNext?.addEventListener('click', () => stepLightbox(1));
lightboxImg?.addEventListener('click', toggleLightboxZoom);
lightboxFav?.addEventListener('click', () => {
  const index = Number(lightbox.dataset.index);
  toggleSelect(index);
});

document.addEventListener('keydown', (event) => {
  if (lightbox.hidden) return;
  if (event.key === 'Escape') closeLightbox();
  if (event.key === 'ArrowLeft') stepLightbox(-1);
  if (event.key === 'ArrowRight') stepLightbox(1);
});

async function fetchFolderPage(folderId, pageToken) {
  const q = `'${folderId}' in parents`;
  const base = 'https://www.googleapis.com/drive/v3/files';
  const url = new URL(base);
  url.searchParams.set('q', q);
  url.searchParams.set('pageSize', '100');
  url.searchParams.set('fields', 'nextPageToken,files(id,name,mimeType,size,createdTime)');
  url.searchParams.set('key', driveKey);
  if (pageToken) url.searchParams.set('pageToken', pageToken);

  const response = await fetch(url);
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    const message = body?.error?.message || 'Terjadi kesalahan saat mengambil folder.';
    throw new Error(message);
  }
  return response.json();
}

const clientSearch = document.querySelector('#client-search');
let searchQuery = '';

function rebuildGrid() {
  if (!galleryGrid) return;
  const q = searchQuery.trim().toLowerCase();
  const wasEmpty = q && !galleryGrid.children.length;
  galleryGrid.innerHTML = '';
  if (!q) {
    currentImages.forEach((image, index) => galleryGrid.appendChild(buildItem(image, index)));
    return;
  }
  let shown = 0;
  currentImages.forEach((image, index) => {
    if (image.name.toLowerCase().includes(q)) {
      galleryGrid.appendChild(buildItem(image, index));
      shown++;
    }
  });
  if (!shown && !wasEmpty) {
    galleryNote.textContent = 'Tidak ada foto yang cocok dengan pencarian.';
  }
}

clientSearch?.addEventListener('input', (event) => {
  searchQuery = event.target.value;
  rebuildGrid();
});

function toggleSelect(index) {
  if (selectedIndices.has(index)) {
    selectedIndices.delete(index);
  } else {
    if (selectedIndices.size >= MAX_SELECTIONS) {
      galleryNote.textContent = `Kuota tercapai: maksimal ${MAX_SELECTIONS} foto dapat dipilih.`;
      return;
    }
    selectedIndices.add(index);
  }
  syncSelectionUI();
}

function buildItem(image, index) {
  const div = document.createElement('div');
  div.className = 'gallery-item';
  div.dataset.index = String(index);
  const img = document.createElement('img');
  img.loading = 'lazy';
  img.alt = image.name;
  img.src = thumbnailUrl(image.id);
  const shade = document.createElement('span');
  shade.className = 'item-shade';
  const name = document.createElement('span');
  name.className = 'item-name';
  name.textContent = image.name;
  const number = document.createElement('span');
  number.className = 'item-number';
  number.textContent = `#${formatNumber(index)}`;
  const check = document.createElement('label');
  check.className = 'item-check';
  check.title = 'Pilih untuk diunduh';
  const checkbox = document.createElement('input');
  checkbox.type = 'checkbox';
  checkbox.dataset.index = String(index);
  checkbox.addEventListener('click', (event) => event.stopPropagation());
  checkbox.addEventListener('change', () => toggleSelect(index));
  check.appendChild(checkbox);
  const icon = document.createElement('span');
  icon.className = 'check-mark';
  icon.textContent = '✓';
  check.appendChild(icon);
  const dl = document.createElement('button');
  dl.type = 'button';
  dl.className = 'item-download';
  dl.title = 'Unduh foto ini';
  dl.textContent = '↓';
  dl.addEventListener('click', (event) => {
    event.stopPropagation();
    downloadFiles([image]);
  });
  div.append(img, shade, name, number, check, dl);
  return div;
}

function syncSelectionUI() {
  document.querySelectorAll('.gallery-item').forEach((itemEl) => {
    const index = Number(itemEl.dataset.index);
    const selected = selectedIndices.has(index);
    const cb = itemEl.querySelector('input[type="checkbox"]');
    if (cb) cb.checked = selected;
    itemEl.classList.toggle('is-selected', selected);
  });
  updateLightboxFav();

  const count = selectedIndices.size;
  selectCount.textContent = `${count} foto dipilih`;
  selectToolbar.hidden = count === 0 && !window.__shortirExpiryActive;

  selectPanel.hidden = count === 0;
  if (count > 0) {
    const quotaText = Number.isFinite(MAX_SELECTIONS) ? ` / ${MAX_SELECTIONS}` : '';
    selectPanelCount.textContent = `${count}${quotaText} foto dipilih`;
    selectPanelGrid.innerHTML = '';
    [...selectedIndices].sort((a, b) => a - b).forEach((index) => {
      const image = currentImages[index];
      if (!image) return;
      const cell = document.createElement('div');
      cell.className = 'panel-item';
      const img = document.createElement('img');
      img.src = image.url || thumbnailUrl(image.id);
      img.alt = image.name;
      const label = document.createElement('span');
      label.textContent = `#${formatNumber(index)}`;
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'panel-remove';
      remove.title = 'Hapus dari pilihan';
      remove.textContent = '×';
      remove.addEventListener('click', () => toggleSelect(index));
      cell.append(img, label, remove);
      selectPanelGrid.appendChild(cell);
    });
  }
}

function updateLightboxFav() {
  if (!lightboxFav) return;
  const index = Number(lightbox.dataset.index);
  const selected = selectedIndices.has(index);
  lightboxFav.textContent = selected ? '♥ Terpilih' : '♡ Pilih foto';
  lightboxFav.classList.toggle('is-fav', selected);
}

function downloadFiles(files) {
  files.forEach((file, i) => {
    setTimeout(() => {
      const a = document.createElement('a');
      a.href = `https://drive.google.com/uc?export=download&id=${encodeURIComponent(file.id)}`;
      a.download = file.name;
      a.target = '_blank';
      a.rel = 'noopener';
      document.body.appendChild(a);
      a.click();
      a.remove();
    }, i * 250);
  });
}

selectDownloadBtn?.addEventListener('click', () => {
  const files = [...selectedIndices].map((index) => currentImages[index]).filter(Boolean);
  downloadFiles(files);
});

selectClearBtn?.addEventListener('click', () => {
  selectedIndices.clear();
  syncSelectionUI();
});

selectPanelClear?.addEventListener('click', () => {
  selectedIndices.clear();
  syncSelectionUI();
});

async function loadFolder(append) {
  try {
    if (!append) {
      renderSkeleton(12);
      currentImages = [];
      nextPageToken = null;
      galleryNote.textContent = 'Mengambil foto dari folder…';
      loadMoreBtn.hidden = true;
      selectedIndices.clear();
      syncSelectionUI();
    }

    const data = await fetchFolderPage(currentFolderId, nextPageToken);
    const images = data.files.filter((f) => f.mimeType.startsWith('image/'));
    const start = currentImages.length;
    currentImages.push(...images);
    nextPageToken = data.nextPageToken || null;

    if (!append) galleryGrid.innerHTML = '';

    if (searchQuery.trim()) {
      rebuildGrid();
    } else {
      images.forEach((image, i) => {
        galleryGrid.appendChild(buildItem(image, start + i));
      });
    }

    loadMoreBtn.hidden = !nextPageToken;

    if (currentImages.length === 0) {
      galleryNote.textContent = 'Tidak ada foto di folder ini. Pastikan folder berisi foto dan aksesnya “Anyone with the link”.';
    } else {
      galleryNote.textContent = `Menampilkan ${currentImages.length} foto${nextPageToken ? ' (dan masih ada lagi)' : ''} dari folder Google Drive publik.`;
    }
  } catch (error) {
    galleryGrid.innerHTML = '';
    galleryNote.textContent = `Gagal memuat galeri: ${error.message}`;
    loadMoreBtn.hidden = true;
    throw error;
  }
}

function showDriveEmbed(folderId) {
  const embed = document.querySelector('#drive-embed');
  galleryGrid.innerHTML = '';
  loadMoreBtn.hidden = true;
  if (selectToolbar) selectToolbar.hidden = true;
  if (selectPanel) selectPanel.hidden = true;
  selectedIndices.clear();
  if (embed) {
    const frame = document.createElement('iframe');
    frame.src = `https://drive.google.com/embeddedfolderview?id=${encodeURIComponent(folderId)}#grid`;
    frame.title = 'Pratinjau folder Google Drive';
    frame.setAttribute('allowfullscreen', '');
    frame.loading = 'lazy';
    embed.replaceChildren(frame);
    embed.hidden = false;
    galleryNote.textContent = 'Menampilkan folder Google Drive langsung dari Drive.';
  } else {
    galleryNote.textContent = 'Gagal memuat galeri: koneksi ke Google Drive tidak tersedia.';
  }
}

function openGallery(folderId) {
  currentFolderId = folderId;
  if (galleryEmpty) galleryEmpty.hidden = true;
  galleryFrameWrap.hidden = false;
  loadFolder(false).catch(() => showDriveEmbed(folderId));
}

loadMoreBtn?.addEventListener('click', () => loadFolder(true));

const autoFolderUrl = params.get('url');
function loadGalleryUrl(url) {
  if (!url) return;
  const folderId = getDriveFolderId(url);
  if (!folderId) return;
  if (isExpired()) {
    galleryNote.textContent = 'Galeri ini telah kedaluwarsa. Hubungi pemilik galeri untuk perpanjangan.';
    return;
  }
  if (driveKey) openGallery(folderId);
  else showDriveEmbed(folderId);
}
window.shortirLoadIfDeferred = () => loadGalleryUrl(autoFolderUrl);
window.shortirOpenByFolder = (url) => loadGalleryUrl(url);
if (!window.__shortirDeferLoad) loadGalleryUrl(autoFolderUrl);

window.shortirGetSelected = () => [...selectedIndices].map((index) => currentImages[index]).filter(Boolean);
window.shortirSelectedCount = () => selectedIndices.size;
window.shortirUnselectFile = (id) => {
  const index = currentImages.findIndex((f) => f.id === id);
  if (index >= 0) toggleSelect(index);
};

const fabToggle = document.querySelector('#fab-toggle');
const fabPopover = document.querySelector('#fab-popover');
fabToggle?.addEventListener('click', () => {
  const isOpen = fabToggle.getAttribute('aria-expanded') === 'true';
  fabToggle.setAttribute('aria-expanded', String(!isOpen));
  fabPopover.hidden = isOpen;
});
document.addEventListener('click', (event) => {
  if (!fabToggle || fabPopover.hidden) return;
  if (!event.target.closest('.fab')) {
    fabToggle.setAttribute('aria-expanded', 'false');
    fabPopover.hidden = true;
  }
});
