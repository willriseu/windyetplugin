<div class="zanka-embedded-host">
    <button
        class="zanka-settings-fab"
        class:is-open={settingsOpen}
        style:left={`${settingsPosition.x}px`}
        style:top={`${settingsPosition.y}px`}
        type="button"
        title={settingsOpen ? 'Beállítások elrejtése' : 'Beállítások megjelenítése'}
        aria-label={settingsOpen ? 'Beállítások elrejtése' : 'Beállítások megjelenítése'}
        on:click={() => settingsOpen = !settingsOpen}
    >
        {settingsOpen ? '×' : '⚙'}
    </button>

    {#if settingsOpen}
        <section class="zanka-panel zanka-floating-settings" bind:this={panelContentRoot} style:left={`${settingsPosition.x}px`} style:top={`${settingsPosition.y}px`}>
            <div class="zanka-panel-title zanka-drag-handle" on:pointerdown={(event) => startDrag('settings', event)}>
                <span>{title}</span>
                <button type="button" title="Panel összecsukása" aria-label="Panel összecsukása" on:click={() => settingsOpen = false}>×</button>
            </div>

            <div class="status-row">
                <span class:online={dataOnline} class:offline={!dataOnline}></span>
                <span>{dataOnline ? 'OKF viharjelzési adatkapcsolat' : 'Viharjelzési adat nem érhető el'}</span>
                <button class="icon-button" title="Hang be/ki" on:click={() => muted = !muted}>{muted ? '🔇' : '🔊'}</button>
            </div>

            <div class="sound-tests">
                <span>Hangteszt:</span>
                <button on:click={() => testSound(0)}>0</button>
                <button on:click={() => testSound(1)}>I</button>
                <button on:click={() => testSound(2)}>II</button>
            </div>

            <div class="camp-actions">
                <button class="action" on:click={focusCamp}>Tábor középre</button>
                <button class="action" on:click={toggleRange}>{rangeVisible ? '30 km-es kör elrejtése' : '30 km-es kör mutatása'}</button>
                <button class="action" on:click={toggleBasinIcons}>{basinIconsVisible ? 'Viharjelző ikonok elrejtése' : 'Viharjelző ikonok mutatása'}</button>
            </div>

            <div class="section-title">Dynamic Island teszt</div>
            <div class="notification-tests">
                <button on:click={() => enqueueTest('storm1')}>I. fok</button>
                <button on:click={() => enqueueTest('storm2')}>II. fok</button>
                <button on:click={() => enqueueTest('zone')}>30 km-es zóna</button>
                <button on:click={() => enqueueTest('camp')}>Tábor érintett</button>
                <button on:click={() => enqueueTest('fire')}>Tűztilalom</button>
                <button on:click={() => enqueueTest('met')}>HungaroMet</button>
            </div>

            <div class="updated">Viharjelzés: {lastUpdated || '—'} · Tűztilalom: {fireUpdated || '—'}</div>
        </section>
    {/if}
</div>

<script lang="ts">
    import bcast from '@windy/broadcast';
    import { map, centerMap } from '@windy/map';
    import { onDestroy, onMount } from 'svelte';
    import config from './pluginConfig';

    const { title } = config;
    const ASSET_ROOT = new URL('./assets/', import.meta.url).href.replace(/\/$/, '');

    const CAMP_CENTER = { lat: 46.879283552225075, lon: 17.7061836229677 };
    const CAMP_RADIUS = 30000;
    const CAMP_POLYGON: Array<[number, number]> = [
        [46.88752821387564, 17.702254940055013],
        [46.88731120424737, 17.709663932622334],
        [46.88190979286378, 17.712945057903028],
        [46.87146146006401, 17.714837259774242],
        [46.87103889057451, 17.707757011478407],
        [46.885058738157426, 17.697529986161157],
    ];

    const OKF_URL = 'https://www.katasztrofavedelem.hu/application/uploads/cache/viharjelzo/SWSStations.json';
    const FIRE_MAP_URL = 'https://www.katasztrofavedelem.hu/application/uploads/cache/NEBIH/nebihTerkep.png';
    const DATA_REFRESH_MS = 60_000;
    const FIRE_REFRESH_MS = 30 * 60_000;
    const WEATHER_REFRESH_MS = 5 * 60_000;
    const WEATHER_URL = `https://api.open-meteo.com/v1/forecast?latitude=${CAMP_CENTER.lat}&longitude=${CAMP_CENTER.lon}&current=temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m,surface_pressure&wind_speed_unit=kmh&timezone=Europe%2FBudapest`;
    const BASE_ISLAND_WIDTH = 228;
    const ISLAND_HEIGHT = 30;

    type Level = 0 | 1 | 2;
    type BasinKey = 'west' | 'central' | 'east';
    type Basin = { key: BasinKey; name: string; level: Level };
    type FireState = 'ban' | 'clear' | 'unknown';
    type NotificationTone = 'clear' | 'warning' | 'danger' | 'info' | 'purple';
    type Notice = { title: string; icon: string; tone: NotificationTone; duration?: number };
    type WeatherData = { temperature: number | null; humidity: number | null; windSpeed: number | null; windDirection: number | null; pressure: number | null; updated: string; online: boolean };
    type LightningStrike = { lat: number; lon: number; time: number; distanceKm: number };
    type LightningData = { nearestKm: number | null; count30m30km: number; updated: string; online: boolean };
    type Point = { x: number; y: number };
    type DragTarget = 'top' | 'weather' | 'settings' | null;

    let basins: Basin[] = [
        { key: 'west', name: 'Nyugati medence', level: 0 },
        { key: 'central', name: 'Középső medence', level: 0 },
        { key: 'east', name: 'Keleti medence', level: 0 },
    ];

    let settingsOpen = true;
    let weatherOpen = true;
    let settingsPosition: Point = { x: 18, y: 520 };
    let topPosition: Point | null = null;
    let weatherPosition: Point = { x: 18, y: 82 };
    let dragTarget: DragTarget = null;
    let dragStartPointer: Point = { x: 0, y: 0 };
    let dragStartElement: Point = { x: 0, y: 0 };
    let dataOnline = false;
    let lastUpdated = '';
    let fireUpdated = '';
    let fireState: FireState = 'unknown';
    let muted = false;
    let rangeVisible = true;
    let basinIconsVisible = true;
    let weatherData: WeatherData = { temperature: null, humidity: null, windSpeed: null, windDirection: null, pressure: null, updated: '', online: false };
    let lightningData: LightningData = { nearestKm: null, count30m30km: 0, updated: '', online: false };
    let lightningSocket: WebSocket | null = null;
    let lightningReconnectTimer: ReturnType<typeof setTimeout> | null = null;
    let lightningCleanupTimer: ReturnType<typeof setInterval> | null = null;
    let lightningServerIndex = 0;
    const lightningHistory: LightningStrike[] = [];
    const LIGHTNING_SERVERS = ['wss://ws1.blitzortung.org/', 'wss://ws7.blitzortung.org/', 'wss://ws8.blitzortung.org/'];

    let centerDot: L.CircleMarker | null = null;
    let rangeCircle: L.Circle | null = null;
    let campPolygon: L.Polygon | null = null;

    let islandRoot: HTMLDivElement | null = null;
    let basinRoot: HTMLDivElement | null = null;
    let brandRoot: HTMLImageElement | null = null;
    let weatherRoot: HTMLDivElement | null = null;
    let weatherFabRoot: HTMLButtonElement | null = null;
    let panelContentRoot: HTMLElement | null = null;
    let portalStyle: HTMLStyleElement | null = null;
    let bodyObserver: MutationObserver | null = null;
    let logoObserver: ResizeObserver | null = null;
    let uiObserver: MutationObserver | null = null;
    let updatePositionRaf = 0;
    let stormTimer: ReturnType<typeof setInterval> | null = null;
    let fireTimer: ReturnType<typeof setInterval> | null = null;
    let weatherTimer: ReturnType<typeof setInterval> | null = null;
    let notificationTimer: ReturnType<typeof setTimeout> | null = null;
    let processingQueue = false;
    let notificationQueue: Notice[] = [];
    let previousCentral: Level | null = null;
    let audioContext: AudioContext | null = null;
    let audioUnlocked = false;

    function ensureAudioContext(): AudioContext | null {
        try {
            if (!audioContext) {
                const AudioContextCtor = window.AudioContext || (window as any).webkitAudioContext;
                audioContext = AudioContextCtor ? new AudioContextCtor() : null;
            }
            return audioContext;
        } catch {
            return null;
        }
    }

    async function unlockAudio() {
        const context = ensureAudioContext();
        if (!context) return;
        try {
            if (context.state === 'suspended') await context.resume();
            audioUnlocked = context.state === 'running';
        } catch {
            audioUnlocked = false;
        }
    }

    async function playPushChime(force = false) {
        if (muted && !force) return;
        const context = ensureAudioContext();
        if (!context) return;
        try {
            if (context.state === 'suspended') await context.resume();
            const now = context.currentTime;
            const gain = context.createGain();
            gain.gain.setValueAtTime(0.0001, now);
            gain.gain.exponentialRampToValueAtTime(0.20, now + 0.015);
            gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.55);
            gain.connect(context.destination);
            for (const [frequency, offset] of [[660, 0], [880, 0.11]] as Array<[number, number]>) {
                const oscillator = context.createOscillator();
                oscillator.type = 'sine';
                oscillator.frequency.setValueAtTime(frequency, now + offset);
                oscillator.connect(gain);
                oscillator.start(now + offset);
                oscillator.stop(now + offset + 0.34);
            }
        } catch (error) {
            console.warn('A push hang nem indítható.', error);
        }
    }

    async function playTerritoryPushSound(force = false) {
        if (muted && !force) return;
        try {
            await unlockAudio();
            const audio = new Audio(asset('territory-push.mp3'));
            audio.preload = 'auto';
            audio.volume = 0.92;
            await audio.play();
        } catch (error) {
            console.warn('A területi push hang nem indítható.', error);
            await playPushChime(force);
        }
    }

    function asset(name: string): string {
        return `${ASSET_ROOT}/${name}`;
    }

    function drawCampLayers() {
        removeCampLayers();
        campPolygon = L.polygon(CAMP_POLYGON, {
            color: '#facc15', weight: 3, fillColor: '#facc15', fillOpacity: 0.10, interactive: false,
        }).addTo(map);
        centerDot = L.circleMarker([CAMP_CENTER.lat, CAMP_CENTER.lon], {
            radius: 7, color: '#fff', weight: 2, fillColor: '#1677ff', fillOpacity: 1, interactive: false,
        }).addTo(map);
        rangeCircle = L.circle([CAMP_CENTER.lat, CAMP_CENTER.lon], {
            radius: CAMP_RADIUS, color: '#22d3ee', weight: 2, fillOpacity: 0.02, dashArray: '8 7', interactive: false,
        });
        if (rangeVisible) rangeCircle.addTo(map);
    }

    function removeCampLayers() {
        campPolygon?.remove();
        centerDot?.remove();
        rangeCircle?.remove();
        campPolygon = null;
        centerDot = null;
        rangeCircle = null;
    }

    function focusCamp() {
        centerMap({ lat: CAMP_CENTER.lat, lon: CAMP_CENTER.lon, zoom: 11 });
    }

    function toggleRange() {
        rangeVisible = !rangeVisible;
        if (!rangeCircle) return;
        if (rangeVisible) rangeCircle.addTo(map);
        else rangeCircle.remove();
    }

    function toggleBasinIcons() {
        basinIconsVisible = !basinIconsVisible;
        renderBasinIcons();
    }

    function normalizeText(value: unknown): string {
        return String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    }

    function groupLevel(groups: any[], term: string): Level | null {
        const group = groups.find(item => {
            const name = normalizeText(item?.name);
            return name.includes('balaton') && name.includes(term) && name.includes('medence');
        });
        const level = Number(group?.level);
        return level === 0 || level === 1 || level === 2 ? (level as Level) : null;
    }

    function labelForLevel(level: Level): string {
        return level === 2 ? 'II. fokú viharjelzés' : level === 1 ? 'I. fokú viharjelzés' : 'Nincs viharjelzés';
    }

    function audioForLevel(level: Level): string {
        return asset(level === 2 ? 'masodfok.mp3' : level === 1 ? 'elsofok.mp3' : 'nincs_riasztas.mp3');
    }

    async function playLevelSound(level: Level, force = false) {
        if (muted && !force) return;
        try {
            await unlockAudio();
            const audio = new Audio(audioForLevel(level));
            audio.preload = 'auto';
            audio.volume = 0.9;
            await audio.play();
        } catch (error) {
            console.warn('A viharjelzési hang nem indítható, push hang következik.', error);
            await playPushChime(force);
        }
    }

    async function testSound(level: Level) {
        await playLevelSound(level, true);
    }

    function fireBaseNotice(): Notice {
        if (fireState === 'ban') return { title: 'Tűzgyújtási tilalom érvényben', icon: 'fire.svg', tone: 'danger' };
        if (fireState === 'clear') return { title: 'Nincs tűzgyújtási tilalom', icon: 'fire.svg', tone: 'clear' };
        return { title: 'Tűzgyújtási állapot nem elérhető', icon: 'fire.svg', tone: 'info' };
    }

    function renderIslandContent(notice: Notice, expanded: boolean) {
        if (!islandRoot) return;
        const text = islandRoot.querySelector('.zanka-island-text') as HTMLSpanElement | null;
        const icon = islandRoot.querySelector('.zanka-island-icon') as HTMLImageElement | null;
        if (!text || !icon) return;

        islandRoot.dataset.tone = notice.tone;
        islandRoot.classList.add('content-changing');
        setTimeout(() => {
            text.textContent = notice.title;
            icon.src = asset(notice.icon);
            const targetWidth = expanded
                ? Math.min(520, Math.max(BASE_ISLAND_WIDTH, Math.ceil(measureTextWidth(notice.title) + 72)))
                : BASE_ISLAND_WIDTH;
            islandRoot?.style.setProperty('--island-width', `${targetWidth}px`);
            islandRoot?.classList.toggle('is-expanded', expanded);
            requestAnimationFrame(() => islandRoot?.classList.remove('content-changing'));
        }, 120);
    }

    function measureTextWidth(text: string): number {
        const canvas = document.createElement('canvas');
        const context = canvas.getContext('2d');
        if (!context) return text.length * 7;
        context.font = '600 13px -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif';
        return context.measureText(text).width;
    }

    function enqueueNotice(notice: Notice) {
        notificationQueue.push(notice);
        void processNotificationQueue();
    }

    async function processNotificationQueue() {
        if (processingQueue || !islandRoot) return;
        processingQueue = true;
        while (notificationQueue.length) {
            const notice = notificationQueue.shift() as Notice;
            renderIslandContent(notice, true);
            await wait(notice.duration ?? 4800);
            renderIslandContent(fireBaseNotice(), false);
            await wait(650);
        }
        processingQueue = false;
    }

    function wait(ms: number): Promise<void> {
        return new Promise(resolve => {
            notificationTimer = setTimeout(resolve, ms);
        });
    }

    async function enqueueTest(kind: 'storm1' | 'storm2' | 'zone' | 'camp' | 'fire' | 'met') {
        const notices: Record<typeof kind, Notice> = {
            storm1: { title: 'Középső medence: I. fokú viharjelzés', icon: 'warning.svg', tone: 'warning' },
            storm2: { title: 'Középső medence: II. fokú viharjelzés', icon: 'warning.svg', tone: 'danger' },
            zone: { title: 'Zivatar a közelben · belépett a 30 km-es zónába', icon: 'storm.svg', tone: 'info' },
            camp: { title: 'A zivatar elérte a tábor kijelölt területét', icon: 'camp.svg', tone: 'purple' },
            fire: { title: 'Tűzgyújtási tilalom lépett életbe', icon: 'fire.svg', tone: 'danger' },
            met: { title: 'HungaroMet riasztás · zivatar veszélye', icon: 'warning.svg', tone: 'warning' },
        };
        await unlockAudio();
        if (kind === 'storm1') await playLevelSound(1, true);
        else if (kind === 'storm2') await playLevelSound(2, true);
        else if (kind === 'zone' || kind === 'camp') await playTerritoryPushSound(true);
        else if (kind !== 'fire') await playPushChime(true);
        enqueueNotice(notices[kind]);
    }

    function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
        const radius = 6371;
        const toRad = (value: number) => value * Math.PI / 180;
        const dLat = toRad(lat2 - lat1);
        const dLon = toRad(lon2 - lon1);
        const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
        return radius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    function decodeLightningFrame(payload: string): string {
        const chars = String(payload).split('');
        if (!chars.length) return '';
        let current = chars[0];
        let phrase = current;
        const output = [current];
        let code = 256;
        const dictionary: Record<number, string> = {};
        for (let index = 1; index < chars.length; index += 1) {
            const value = chars[index].charCodeAt(0);
            const entry = value < 256 ? chars[index] : (dictionary[value] || phrase + current);
            output.push(entry);
            current = entry.charAt(0);
            dictionary[code++] = phrase + current;
            phrase = entry;
        }
        return output.join('');
    }

    function normalizeStrikeTime(raw: unknown): number {
        const value = Number(raw ?? Date.now());
        if (!Number.isFinite(value)) return Date.now();
        if (value > 1e14) return value / 1e6;
        if (value > 1e12) return value;
        return value * 1000;
    }

    function updateLightningDashboard() {
        const cutoff = Date.now() - 30 * 60_000;
        while (lightningHistory.length && lightningHistory[0].time < cutoff) lightningHistory.shift();
        const nearest = lightningHistory.length ? Math.min(...lightningHistory.map(item => item.distanceKm)) : null;
        const count30m30km = lightningHistory.filter(item => item.distanceKm <= 30).length;
        lightningData = {
            nearestKm: nearest,
            count30m30km,
            updated: lightningData.updated,
            online: lightningData.online,
        };
        renderWeatherPanel();
    }

    function addLightningStrike(data: any) {
        const lat = Number(data?.lat ?? data?.latitude);
        const lon = Number(data?.lon ?? data?.lng ?? data?.longitude);
        if (!Number.isFinite(lat) || !Number.isFinite(lon)) return;
        const time = normalizeStrikeTime(data?.time ?? data?.timestamp);
        if (Date.now() - time > 30 * 60_000) return;
        const distanceKm = haversineKm(lat, lon, CAMP_CENTER.lat, CAMP_CENTER.lon);
        lightningHistory.push({ lat, lon, time, distanceKm });
        lightningHistory.sort((a, b) => a.time - b.time);
        lightningData = {
            ...lightningData,
            online: true,
            updated: new Intl.DateTimeFormat('hu-HU', { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(new Date(time)),
        };
        updateLightningDashboard();
    }

    function parseLightningPayload(payload: string): boolean {
        try {
            const decoded = decodeLightningFrame(payload);
            const parsed = JSON.parse(decoded);
            if (Array.isArray(parsed)) { parsed.forEach(addLightningStrike); return parsed.length > 0; }
            if (parsed && Array.isArray(parsed.strokes)) { parsed.strokes.forEach(addLightningStrike); return parsed.strokes.length > 0; }
            if (parsed && (parsed.lat !== undefined || parsed.latitude !== undefined)) { addLightningStrike(parsed); return true; }
        } catch {
            // A Blitzortung adatfolyam állapotüzeneteket is küldhet.
        }
        return false;
    }

    function scheduleLightningReconnect() {
        if (lightningReconnectTimer) clearTimeout(lightningReconnectTimer);
        lightningReconnectTimer = setTimeout(() => {
            lightningServerIndex = (lightningServerIndex + 1) % LIGHTNING_SERVERS.length;
            connectLightning();
        }, 2500);
    }

    function connectLightning() {
        if (lightningSocket && lightningSocket.readyState <= 1) return;
        try {
            const socket = new WebSocket(LIGHTNING_SERVERS[lightningServerIndex]);
            lightningSocket = socket;
            socket.onopen = () => {
                lightningData = { ...lightningData, online: true };
                renderWeatherPanel();
                try { socket.send(JSON.stringify({ a: 111 })); } catch { /* nincs teendő */ }
            };
            socket.onmessage = event => { parseLightningPayload(String(event.data)); };
            socket.onerror = () => { try { socket.close(); } catch { /* nincs teendő */ } };
            socket.onclose = () => {
                if (lightningSocket === socket) lightningSocket = null;
                lightningData = { ...lightningData, online: false };
                renderWeatherPanel();
                scheduleLightningReconnect();
            };
        } catch (error) {
            console.warn('Blitzortung kapcsolódási hiba:', error);
            lightningData = { ...lightningData, online: false };
            renderWeatherPanel();
            scheduleLightningReconnect();
        }
    }

    function stopLightning() {
        if (lightningReconnectTimer) clearTimeout(lightningReconnectTimer);
        if (lightningCleanupTimer) clearInterval(lightningCleanupTimer);
        lightningReconnectTimer = null;
        lightningCleanupTimer = null;
        if (lightningSocket) {
            const socket = lightningSocket;
            lightningSocket = null;
            try { socket.onclose = null; socket.close(); } catch { /* nincs teendő */ }
        }
    }

    function compassDirection(degrees: number | null): string {
        if (degrees === null || !Number.isFinite(degrees)) return '—';
        const labels = ['É', 'ÉK', 'K', 'DK', 'D', 'DNy', 'Ny', 'ÉNy'];
        return labels[Math.round(((degrees % 360) + 360) % 360 / 45) % 8];
    }

    function formatWeatherValue(value: number | null, digits = 0): string {
        return value === null || !Number.isFinite(value) ? '—' : value.toFixed(digits);
    }

    function readSavedPoint(key: string, fallback: Point): Point {
        try {
            const parsed = JSON.parse(localStorage.getItem(key) || 'null');
            if (Number.isFinite(parsed?.x) && Number.isFinite(parsed?.y)) return { x: parsed.x, y: parsed.y };
        } catch { /* use fallback */ }
        return fallback;
    }

    function savePoint(key: string, point: Point | null) {
        try {
            if (point) localStorage.setItem(key, JSON.stringify(point));
            else localStorage.removeItem(key);
        } catch { /* storage unavailable */ }
    }

    function clampPoint(point: Point, width: number, height: number): Point {
        return {
            x: Math.max(8, Math.min(window.innerWidth - width - 8, point.x)),
            y: Math.max(8, Math.min(window.innerHeight - height - 8, point.y)),
        };
    }

    function startDrag(target: Exclude<DragTarget, null>, event: PointerEvent) {
        const element = event.target as HTMLElement;
        if (element.closest('button')) return;
        event.preventDefault();
        dragTarget = target;
        dragStartPointer = { x: event.clientX, y: event.clientY };
        if (target === 'top' && islandRoot) {
            const rect = islandRoot.getBoundingClientRect();
            dragStartElement = { x: rect.left + rect.width / 2, y: rect.top };
        } else if (target === 'weather' && weatherRoot) {
            const rect = weatherRoot.getBoundingClientRect();
            dragStartElement = { x: rect.left, y: rect.top };
        } else {
            dragStartElement = { ...settingsPosition };
        }
        document.documentElement.classList.add('zanka-is-dragging');
        window.addEventListener('pointermove', handleDragMove, { passive: false });
        window.addEventListener('pointerup', finishDrag, { once: true });
        window.addEventListener('pointercancel', finishDrag, { once: true });
    }

    function handleDragMove(event: PointerEvent) {
        if (!dragTarget) return;
        event.preventDefault();
        const dx = event.clientX - dragStartPointer.x;
        const dy = event.clientY - dragStartPointer.y;
        if (dragTarget === 'top') {
            const halfWidth = Math.max(BASE_ISLAND_WIDTH, islandRoot?.getBoundingClientRect().width || BASE_ISLAND_WIDTH) / 2;
            topPosition = {
                x: Math.max(halfWidth + 8, Math.min(window.innerWidth - halfWidth - 8, dragStartElement.x + dx)),
                y: Math.max(8, Math.min(window.innerHeight - 115, dragStartElement.y + dy)),
            };
            savePoint('zanka.topPosition', topPosition);
            applyTopPosition();
        } else if (dragTarget === 'weather' && weatherRoot) {
            weatherPosition = clampPoint({ x: dragStartElement.x + dx, y: dragStartElement.y + dy }, weatherRoot.offsetWidth || 224, weatherRoot.offsetHeight || 360);
            savePoint('zanka.weatherPosition', weatherPosition);
            applyWeatherPosition();
        } else if (dragTarget === 'settings') {
            const panel = panelContentRoot;
            settingsPosition = clampPoint({ x: dragStartElement.x + dx, y: dragStartElement.y + dy }, panel?.offsetWidth || 320, panel?.offsetHeight || 300);
            savePoint('zanka.settingsPosition', settingsPosition);
        }
    }

    function finishDrag() {
        dragTarget = null;
        document.documentElement.classList.remove('zanka-is-dragging');
        window.removeEventListener('pointermove', handleDragMove);
    }

    function applyTopPosition() {
        if (!topPosition || !islandRoot || !basinRoot) return;
        islandRoot.style.left = `${Math.round(topPosition.x)}px`;
        islandRoot.style.top = `${Math.round(topPosition.y)}px`;
        basinRoot.style.left = `${Math.round(topPosition.x)}px`;
        basinRoot.style.top = `${Math.round(topPosition.y + ISLAND_HEIGHT + 10)}px`;
    }

    function applyWeatherPosition() {
        const target = weatherOpen ? weatherRoot : weatherFabRoot;
        if (!target) return;
        const width = target.offsetWidth || (weatherOpen ? 224 : 42);
        const height = target.offsetHeight || (weatherOpen ? 360 : 42);
        weatherPosition = clampPoint(weatherPosition, width, height);
        target.style.left = `${Math.round(weatherPosition.x)}px`;
        target.style.top = `${Math.round(weatherPosition.y)}px`;
    }

    function setWeatherOpen(open: boolean) {
        weatherOpen = open;
        if (weatherRoot) weatherRoot.style.display = open ? 'block' : 'none';
        if (weatherFabRoot) weatherFabRoot.style.display = open ? 'none' : 'flex';
        requestAnimationFrame(applyWeatherPosition);
    }

    function renderWeatherPanel() {
        if (!weatherRoot) return;
        const direction = compassDirection(weatherData.windDirection);
        const directionDegrees = weatherData.windDirection === null ? '' : ` (${Math.round(weatherData.windDirection)}°)`;
        weatherRoot.innerHTML = `
            <div class="zanka-weather-title zanka-drag-handle"><span>TÁBOR – AKTUÁLIS IDŐJÁRÁS</span><button type="button" class="zanka-weather-close" title="Összecsukás" aria-label="Összecsukás">×</button></div>
            <div class="zanka-weather-row"><img src="${asset('weather-temperature.svg')}" alt=""><span>Hőmérséklet</span><strong>${formatWeatherValue(weatherData.temperature, 1)} °C</strong></div>
            <div class="zanka-weather-row"><img src="${asset('weather-humidity.svg')}" alt=""><span>Páratartalom</span><strong>${formatWeatherValue(weatherData.humidity)} %</strong></div>
            <div class="zanka-weather-row"><img src="${asset('weather-direction.svg')}" alt=""><span>Szélirány</span><strong>${direction}${directionDegrees}</strong></div>
            <div class="zanka-weather-row"><img src="${asset('weather-wind.svg')}" alt=""><span>Szél erőssége</span><strong>${formatWeatherValue(weatherData.windSpeed)} km/h</strong></div>
            <div class="zanka-weather-row"><img src="${asset('weather-pressure.svg')}" alt=""><span>Légnyomás</span><strong>${formatWeatherValue(weatherData.pressure)} hPa</strong></div>
            <div class="zanka-weather-separator"></div>
            <div class="zanka-weather-row zanka-lightning-row"><img src="${asset('weather-lightning.svg')}" alt=""><span>Legközelebbi villám</span><strong>${lightningData.nearestKm === null ? '—' : `${lightningData.nearestKm.toFixed(1)} km`}</strong></div>
            <div class="zanka-weather-row zanka-lightning-row"><img src="${asset('weather-lightning.svg')}" alt=""><span>Villámlások száma</span><strong>${lightningData.count30m30km} db</strong><small>30 km / 30 perc</small></div>
            <div class="zanka-weather-footer"><span>${weatherData.online ? `Időjárás: ${weatherData.updated}` : 'Időjárási adat nem érhető el'} · ${lightningData.online ? `Villám: ${lightningData.updated || 'élő'}` : 'Villám: kapcsolódás…'}</span><button type="button" class="zanka-weather-refresh" aria-label="Frissítés">↻</button></div>`;
        weatherRoot.querySelector('.zanka-weather-refresh')?.addEventListener('click', () => void loadLocalWeather());
        weatherRoot.querySelector('.zanka-weather-close')?.addEventListener('click', () => setWeatherOpen(false));
        weatherRoot.querySelector('.zanka-weather-title')?.addEventListener('pointerdown', event => startDrag('weather', event as PointerEvent));
        setWeatherOpen(weatherOpen);
    }

    async function loadLocalWeather() {
        try {
            const response = await fetch(`${WEATHER_URL}&_=${Date.now()}`, { cache: 'no-store' });
            if (!response.ok) throw new Error(`Időjárás HTTP ${response.status}`);
            const payload = await response.json();
            const current = payload?.current ?? {};
            weatherData = {
                temperature: Number.isFinite(Number(current.temperature_2m)) ? Number(current.temperature_2m) : null,
                humidity: Number.isFinite(Number(current.relative_humidity_2m)) ? Number(current.relative_humidity_2m) : null,
                windSpeed: Number.isFinite(Number(current.wind_speed_10m)) ? Number(current.wind_speed_10m) : null,
                windDirection: Number.isFinite(Number(current.wind_direction_10m)) ? Number(current.wind_direction_10m) : null,
                pressure: Number.isFinite(Number(current.surface_pressure)) ? Number(current.surface_pressure) : null,
                updated: new Intl.DateTimeFormat('hu-HU', { hour: '2-digit', minute: '2-digit' }).format(new Date()),
                online: true,
            };
        } catch (error) {
            weatherData = { ...weatherData, online: false };
            console.warn('Helyi időjárás lekérési hiba:', error);
        }
        renderWeatherPanel();
    }

    function createPortalUi() {
        destroyPortalUi();

        portalStyle = document.createElement('style');
        portalStyle.id = 'zanka-portal-style';
        portalStyle.textContent = `
            #zanka-dynamic-island{--island-width:${BASE_ISLAND_WIDTH}px;position:fixed;z-index:2147483000;width:var(--island-width);height:${ISLAND_HEIGHT}px;left:50%;top:88px;transform:translateX(-50%);display:flex;align-items:center;gap:9px;padding:0 13px;box-sizing:border-box;border-radius:999px;background:#050505;color:#fff;box-shadow:0 7px 22px rgba(0,0,0,.42),inset 0 0 0 1px rgba(255,255,255,.09);font:600 13px/1 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;white-space:nowrap;overflow:hidden;transition:width .42s cubic-bezier(.22,.9,.25,1),box-shadow .25s ease;pointer-events:auto;cursor:grab;touch-action:none}
            #zanka-dynamic-island:active{cursor:grabbing}
            #zanka-dynamic-island[data-tone="clear"]{--tone:#30d158} #zanka-dynamic-island[data-tone="warning"]{--tone:#ffd60a} #zanka-dynamic-island[data-tone="danger"]{--tone:#ff453a} #zanka-dynamic-island[data-tone="info"]{--tone:#0a84ff} #zanka-dynamic-island[data-tone="purple"]{--tone:#bf5af2}
            #zanka-dynamic-island.is-expanded{box-shadow:0 8px 26px rgba(0,0,0,.52),0 0 18px color-mix(in srgb,var(--tone) 32%,transparent),inset 0 0 0 1px rgba(255,255,255,.11)}
            #zanka-dynamic-island .zanka-island-icon{width:18px;height:18px;flex:0 0 18px;object-fit:contain;transition:opacity .18s ease,transform .22s ease}
            #zanka-dynamic-island .zanka-island-dot{width:9px;height:9px;border-radius:50%;background:var(--tone);box-shadow:0 0 9px var(--tone);flex:0 0 9px}
            #zanka-dynamic-island .zanka-island-text{overflow:hidden;text-overflow:ellipsis;opacity:1;transform:translateY(0);transition:opacity .18s ease,transform .18s ease}
            #zanka-dynamic-island.content-changing .zanka-island-text{opacity:0;transform:translateY(3px)}
            #zanka-dynamic-island.content-changing .zanka-island-icon{opacity:.3;transform:scale(.82)}
            #zanka-basin-row{position:fixed;z-index:2147482999;left:50%;top:128px;transform:translateX(-50%);display:flex;gap:14px;align-items:flex-start;pointer-events:auto;cursor:grab;touch-action:none;transition:opacity .2s ease}
            #zanka-basin-row.is-hidden{opacity:0;visibility:hidden}
            #zanka-brand-logo{position:fixed;z-index:2147483001;width:44px;height:44px;left:calc(50% - 112px);top:28px;object-fit:contain;transform:translate(-100%,-50%);filter:drop-shadow(0 4px 10px rgba(0,0,0,.38));pointer-events:none;display:block;opacity:1}
            #zanka-weather-panel{position:fixed;z-index:2147482998;width:224px;box-sizing:border-box;padding:12px;border-radius:16px;background:rgba(17,18,21,.82);border:1px solid rgba(255,255,255,.13);box-shadow:0 12px 30px rgba(0,0,0,.36);backdrop-filter:blur(15px) saturate(135%);-webkit-backdrop-filter:blur(15px) saturate(135%);color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;transition:left .24s ease,right .24s ease;pointer-events:auto}
            #zanka-weather-panel .zanka-weather-title{font-size:11px;font-weight:800;letter-spacing:.03em;color:#2997ff;margin:0 0 8px;display:flex;align-items:center;justify-content:space-between;cursor:grab;touch-action:none;user-select:none}
            #zanka-weather-panel .zanka-weather-close{width:22px;height:22px;border:0;border-radius:50%;background:transparent;color:#fff;font-size:17px;line-height:1;opacity:.72;cursor:pointer;padding:0}#zanka-weather-panel .zanka-weather-close:hover{opacity:1;background:rgba(255,255,255,.1)}
            #zanka-weather-fab{position:fixed;z-index:2147482998;width:42px;height:42px;border:1px solid rgba(255,255,255,.18);border-radius:50%;display:none;align-items:center;justify-content:center;background:rgba(10,14,22,.9);box-shadow:0 10px 30px rgba(0,0,0,.34);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);cursor:pointer;padding:0;pointer-events:auto}#zanka-weather-fab img{width:22px;height:22px}
            #zanka-weather-panel .zanka-weather-row{height:31px;display:grid;grid-template-columns:22px 1fr auto;align-items:center;gap:7px;padding:0 8px;margin:5px 0;border-radius:10px;background:rgba(255,255,255,.055);box-shadow:inset 0 0 0 1px rgba(255,255,255,.035)}
            #zanka-weather-panel .zanka-weather-row img{width:17px;height:17px;object-fit:contain}
            #zanka-weather-panel .zanka-weather-row span{font-size:10.5px;opacity:.78;white-space:nowrap}
            #zanka-weather-panel .zanka-weather-row strong{font-size:12px;font-weight:750;white-space:nowrap}
            #zanka-weather-panel .zanka-weather-separator{height:1px;margin:8px 5px;background:rgba(255,255,255,.12)}
            #zanka-weather-panel .zanka-lightning-row{position:relative;padding-right:8px}
            #zanka-weather-panel .zanka-lightning-row small{position:absolute;right:8px;bottom:1px;font-size:7px;color:rgba(255,255,255,.48);letter-spacing:.02em}
            #zanka-weather-panel .zanka-weather-footer{display:flex;align-items:center;justify-content:space-between;margin-top:8px;padding:0 3px;font-size:10px;opacity:.72}
            #zanka-weather-panel .zanka-weather-refresh{width:24px;height:24px;border:0;border-radius:50%;background:transparent;color:#fff;font-size:18px;line-height:1;cursor:pointer;padding:0}
            #zanka-weather-panel .zanka-weather-refresh:hover{background:rgba(255,255,255,.1)}
            .zanka-basin{width:58px;text-align:center;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;text-shadow:0 1px 3px rgba(0,0,0,.9)}
            .zanka-basin img{display:block;width:44px;height:44px;margin:0 auto 3px;filter:drop-shadow(0 5px 10px rgba(0,0,0,.35));transition:transform .2s ease,filter .2s ease}
            .zanka-basin span{display:block;font-size:10px;line-height:11px;font-weight:600;white-space:normal}
            .zanka-basin.pulse img{animation:zankaPulse 1.15s cubic-bezier(.2,.8,.2,1)}
            @keyframes zankaPulse{0%{transform:scale(1);filter:drop-shadow(0 0 0 transparent)}45%{transform:scale(1.14);filter:drop-shadow(0 0 12px #ffd60a)}100%{transform:scale(1);filter:drop-shadow(0 5px 10px rgba(0,0,0,.35))}}
        `;
        document.head.appendChild(portalStyle);

        islandRoot = document.createElement('div');
        islandRoot.id = 'zanka-dynamic-island';
        islandRoot.innerHTML = `<img class="zanka-island-icon" alt=""><span class="zanka-island-dot"></span><span class="zanka-island-text"></span>`;
        islandRoot.addEventListener('pointerdown', event => startDrag('top', event));
        document.body.appendChild(islandRoot);

        basinRoot = document.createElement('div');
        basinRoot.id = 'zanka-basin-row';
        basinRoot.addEventListener('pointerdown', event => startDrag('top', event));
        document.body.appendChild(basinRoot);

        brandRoot = document.createElement('img');
        brandRoot.id = 'zanka-brand-logo';
        brandRoot.src = asset('erzsebet_logo.png');
        brandRoot.alt = 'Erzsébet-táborok';
        brandRoot.onerror = () => {
            if (brandRoot && !brandRoot.src.endsWith('/erzsebet-logo.png')) {
                brandRoot.src = asset('erzsebet-logo.png');
            }
        };
        document.body.appendChild(brandRoot);

        weatherRoot = document.createElement('div');
        weatherRoot.id = 'zanka-weather-panel';
        document.body.appendChild(weatherRoot);

        weatherFabRoot = document.createElement('button');
        weatherFabRoot.id = 'zanka-weather-fab';
        weatherFabRoot.type = 'button';
        weatherFabRoot.title = 'Időjárási panel megjelenítése';
        weatherFabRoot.setAttribute('aria-label', 'Időjárási panel megjelenítése');
        weatherFabRoot.innerHTML = `<img src="${asset('weather-temperature.svg')}" alt="">`;
        weatherFabRoot.addEventListener('click', () => setWeatherOpen(true));
        document.body.appendChild(weatherFabRoot);

        topPosition = (() => { const p = readSavedPoint('zanka.topPosition', { x: NaN, y: NaN }); return Number.isFinite(p.x) ? p : null; })();
        weatherPosition = readSavedPoint('zanka.weatherPosition', weatherPosition);
        settingsPosition = readSavedPoint('zanka.settingsPosition', settingsPosition);

        renderIslandContent(fireBaseNotice(), false);
        renderBasinIcons();
        renderWeatherPanel();
        installPortalGuards();
        schedulePositionUpdate();
    }

    function destroyPortalUi() {
        if (updatePositionRaf) cancelAnimationFrame(updatePositionRaf);
        bodyObserver?.disconnect();
        uiObserver?.disconnect();
        logoObserver?.disconnect();
        bodyObserver = null;
        uiObserver = null;
        logoObserver = null;
        islandRoot?.remove();
        basinRoot?.remove();
        brandRoot?.remove();
        weatherRoot?.remove();
        weatherFabRoot?.remove();
        portalStyle?.remove();
        islandRoot = null;
        basinRoot = null;
        brandRoot = null;
        weatherRoot = null;
        weatherFabRoot = null;
        portalStyle = null;
    }

    function installPortalGuards() {
        bodyObserver = new MutationObserver(() => {
            if (islandRoot && islandRoot.parentElement !== document.body) document.body.appendChild(islandRoot);
            if (basinRoot && basinRoot.parentElement !== document.body) document.body.appendChild(basinRoot);
            if (brandRoot && brandRoot.parentElement !== document.body) document.body.appendChild(brandRoot);
            if (weatherRoot && weatherRoot.parentElement !== document.body) document.body.appendChild(weatherRoot);
            if (weatherFabRoot && weatherFabRoot.parentElement !== document.body) document.body.appendChild(weatherFabRoot);
            schedulePositionUpdate();
        });
        bodyObserver.observe(document.body, { childList: true, subtree: true });

        uiObserver = new MutationObserver(schedulePositionUpdate);
        uiObserver.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style'] });
    }

    type LogoBounds = { left: number; right: number; top: number; bottom: number; width: number; height: number };

    function isVisibleElement(el: HTMLElement) {
        const rect = el.getBoundingClientRect();
        const style = getComputedStyle(el);
        return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0;
    }

    function findWindyLogoBounds(): LogoBounds | null {
        const textCandidates = Array.from(document.querySelectorAll('a,div,span'))
            .filter((node): node is HTMLElement => node instanceof HTMLElement)
            .filter(isVisibleElement)
            .filter(el => {
                const compact = (el.textContent || '').replace(/\s+/g, '').toLowerCase();
                const rect = el.getBoundingClientRect();
                return compact.includes('windy.com') && compact.length <= 24 && rect.top >= 0 && rect.top < 170 && rect.width < 260;
            })
            .sort((a, b) => a.getBoundingClientRect().width - b.getBoundingClientRect().width);
        const textEl = textCandidates[0];
        if (!textEl) return null;
        const textRect = textEl.getBoundingClientRect();
        const iconCandidates = Array.from(document.querySelectorAll('img,svg,canvas,div'))
            .filter((node): node is HTMLElement => node instanceof HTMLElement)
            .filter(el => el.id !== 'zanka-brand-logo' && isVisibleElement(el))
            .map(el => el.getBoundingClientRect())
            .filter(r => r.width >= 28 && r.width <= 70 && r.height >= 28 && r.height <= 70)
            .filter(r => Math.abs((r.top + r.bottom) / 2 - (textRect.top + textRect.bottom) / 2) < 24)
            .filter(r => r.right <= textRect.left + 15 && r.right >= textRect.left - 95)
            .sort((a, b) => Math.abs(a.right - textRect.left) - Math.abs(b.right - textRect.left));
        const iconRect = iconCandidates[0];
        const left = iconRect ? Math.min(iconRect.left, textRect.left) : Math.max(0, textRect.left - 58);
        const top = iconRect ? Math.min(iconRect.top, textRect.top) : textRect.top;
        const right = textRect.right;
        const bottom = iconRect ? Math.max(iconRect.bottom, textRect.bottom) : textRect.bottom;
        return { left, right, top, bottom, width: right - left, height: bottom - top };
    }

    function findRightPaneLeft(): number | null {
        if (!panelContentRoot) return null;
        let el: HTMLElement | null = panelContentRoot;
        for (let i = 0; el && i < 7; i += 1, el = el.parentElement) {
            const rect = el.getBoundingClientRect();
            if (rect.width >= 260 && rect.width <= 520 && rect.height > window.innerHeight * 0.65 && rect.right >= window.innerWidth - 8) return rect.left;
        }
        return null;
    }

    function findModelBarTop(): number | null {
        const candidates = Array.from(document.querySelectorAll('div,button,span'))
            .filter((node): node is HTMLElement => node instanceof HTMLElement)
            .filter(isVisibleElement)
            .filter(el => /ECMWF/i.test(el.textContent || ''))
            .map(el => el.getBoundingClientRect())
            .filter(r => r.top > window.innerHeight * 0.55 && r.left > window.innerWidth * 0.45 && r.width > 80 && r.width < 650)
            .sort((a,b) => a.top - b.top);
        return candidates[0]?.top ?? null;
    }

    function schedulePositionUpdate() {
        if (updatePositionRaf) cancelAnimationFrame(updatePositionRaf);
        updatePositionRaf = requestAnimationFrame(updatePortalPosition);
    }

    function updatePortalPosition() {
        if (!islandRoot || !basinRoot) return;
        const logo = findWindyLogoBounds();
        let centerX = window.innerWidth / 2;
        let top = 88;
        if (logo) {
            centerX = logo.left + logo.width / 2;
            top = logo.bottom + 2;
        }
        if (brandRoot) {
            // The Windy logo detector can briefly fail while Windy rebuilds its header.
            // Keep the Erzsébet logo visible using the last/fallback header position.
            const brandSize = logo ? Math.max(38, Math.min(50, logo.height || 44)) : 44;
            const windyLeft = logo ? logo.left : centerX - 88;
            const windyMidY = logo ? logo.top + logo.height / 2 : 28;
            brandRoot.style.width = `${Math.round(brandSize)}px`;
            brandRoot.style.height = `${Math.round(brandSize)}px`;
            brandRoot.style.left = `${Math.round(windyLeft - 6)}px`;
            brandRoot.style.top = `${Math.round(windyMidY)}px`;
            brandRoot.style.display = 'block';
            brandRoot.style.opacity = '1';
        }
        if (topPosition) applyTopPosition();
        else {
            islandRoot.style.left = `${Math.round(centerX)}px`;
            islandRoot.style.top = `${Math.round(top)}px`;
            basinRoot.style.left = `${Math.round(centerX)}px`;
            basinRoot.style.top = `${Math.round(top + ISLAND_HEIGHT + 10)}px`;
        }
        applyWeatherPosition();
    }

    function renderBasinIcons() {
        if (!basinRoot) return;
        basinRoot.classList.toggle('is-hidden', !basinIconsVisible);
        basinRoot.innerHTML = basins.map(basin => `
            <div class="zanka-basin" data-basin="${basin.key}">
                <img src="${asset(`basin_level_${basin.level}.svg`)}" alt="${basin.level}. fok">
                <span>${basin.name.replace(' medence', '<br>medence')}</span>
            </div>
        `).join('');
    }

    function pulseCentralBasin() {
        const element = basinRoot?.querySelector('[data-basin="central"]');
        if (!(element instanceof HTMLElement)) return;
        element.classList.remove('pulse');
        void element.offsetWidth;
        element.classList.add('pulse');
        setTimeout(() => element.classList.remove('pulse'), 1300);
    }

    async function loadStormStatus() {
        try {
            const response = await fetch(`${OKF_URL}?t=${Date.now()}`, { cache: 'no-store' });
            if (!response.ok) throw new Error(`OKF HTTP ${response.status}`);
            const payload = await response.json();
            const groups = Array.isArray(payload?.groups) ? payload.groups : [];
            const statuses = {
                west: groupLevel(groups, 'nyugati'),
                central: groupLevel(groups, 'kozepso'),
                east: groupLevel(groups, 'keleti'),
            };
            if (statuses.west === null || statuses.central === null || statuses.east === null) throw new Error('Hiányzó balatoni medenceadat.');

            basins = basins.map(basin => ({ ...basin, level: statuses[basin.key] as Level }));
            renderBasinIcons();
            dataOnline = true;
            lastUpdated = new Intl.DateTimeFormat('hu-HU', { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(new Date());

            const currentCentral = statuses.central as Level;
            if (previousCentral !== null && currentCentral !== previousCentral) {
                await playLevelSound(currentCentral);
                pulseCentralBasin();
                enqueueNotice({
                    title: currentCentral === 0 ? 'A középső medence viharjelzése megszűnt' : `Középső medence: ${labelForLevel(currentCentral)}`,
                    icon: 'warning.svg',
                    tone: currentCentral === 2 ? 'danger' : currentCentral === 1 ? 'warning' : 'clear',
                });
            }
            previousCentral = currentCentral;
        } catch (error) {
            dataOnline = false;
            console.warn('OKF balatoni viharjelzés lekérési hiba:', error);
        }
    }

    function setFireState(next: FireState, notify = true) {
        const previous = fireState;
        fireState = next;
        fireUpdated = new Intl.DateTimeFormat('hu-HU', { hour: '2-digit', minute: '2-digit' }).format(new Date());
        if (notify && previous !== 'unknown' && previous !== next) {
            enqueueNotice({
                title: next === 'ban' ? 'Tűzgyújtási tilalom lépett életbe' : 'A tűzgyújtási tilalom megszűnt',
                icon: 'fire.svg', tone: next === 'ban' ? 'danger' : 'clear',
            });
        } else if (!processingQueue) {
            renderIslandContent(fireBaseNotice(), false);
        }
    }

    async function checkFireBan() {
        try {
            const image = new Image();
            image.crossOrigin = 'anonymous';
            await new Promise<void>((resolve, reject) => {
                image.onload = () => resolve();
                image.onerror = () => reject(new Error('A tűzgyújtási térkép nem tölthető be.'));
                image.src = `${FIRE_MAP_URL}?t=${Date.now()}`;
            });
            const canvas = document.createElement('canvas');
            canvas.width = image.naturalWidth;
            canvas.height = image.naturalHeight;
            const context = canvas.getContext('2d', { willReadFrequently: true });
            if (!context) throw new Error('Canvas nem érhető el.');
            context.drawImage(image, 0, 0);
            const bbox = { west: 16.05, east: 22.95, south: 45.72, north: 48.62, left: 0.065, right: 0.94, top: 0.055, bottom: 0.91 };
            const px = (bbox.left + (CAMP_CENTER.lon - bbox.west) / (bbox.east - bbox.west) * (bbox.right - bbox.left)) * canvas.width;
            const py = (bbox.top + (bbox.north - CAMP_CENTER.lat) / (bbox.north - bbox.south) * (bbox.bottom - bbox.top)) * canvas.height;
            const sampleSize = 20;
            const sample = context.getImageData(Math.max(0, Math.round(px - 10)), Math.max(0, Math.round(py - 10)), sampleSize, sampleSize).data;
            let red = 0;
            let total = 0;
            for (let index = 0; index < sample.length; index += 4) {
                const [r, g, b, a] = [sample[index], sample[index + 1], sample[index + 2], sample[index + 3]];
                if (a < 80) continue;
                total += 1;
                if (r > 170 && r > g * 1.25 && r > b * 1.2) red += 1;
            }
            setFireState(total && red / total > 0.16 ? 'ban' : 'clear');
        } catch (error) {
            console.warn('Tűzgyújtási tilalom lekérési hiba:', error);
            setFireState('unknown', false);
        }
    }

    function startServices() {
        drawCampLayers();
        createPortalUi();
        void loadStormStatus();
        void checkFireBan();
        void loadLocalWeather();
        connectLightning();
        if (!lightningCleanupTimer) lightningCleanupTimer = setInterval(updateLightningDashboard, 30_000);
        if (!stormTimer) stormTimer = setInterval(loadStormStatus, DATA_REFRESH_MS);
        if (!fireTimer) fireTimer = setInterval(checkFireBan, FIRE_REFRESH_MS);
        if (!weatherTimer) weatherTimer = setInterval(loadLocalWeather, WEATHER_REFRESH_MS);
    }

    export const onopen = () => {
        startServices();
        focusCamp();
    };

    onMount(() => {
        startServices();
        window.addEventListener('resize', schedulePositionUpdate);
        window.addEventListener('orientationchange', schedulePositionUpdate);
        document.addEventListener('pointerdown', unlockAudio, { once: true, capture: true });
        document.addEventListener('keydown', unlockAudio, { once: true, capture: true });
    });

    onDestroy(() => {
        if (stormTimer) clearInterval(stormTimer);
        if (fireTimer) clearInterval(fireTimer);
        if (weatherTimer) clearInterval(weatherTimer);
        if (notificationTimer) clearTimeout(notificationTimer);
        stormTimer = null;
        fireTimer = null;
        weatherTimer = null;
        notificationTimer = null;
        notificationQueue = [];
        processingQueue = false;
        window.removeEventListener('resize', schedulePositionUpdate);
        window.removeEventListener('orientationchange', schedulePositionUpdate);
        document.removeEventListener('pointerdown', unlockAudio, true);
        document.removeEventListener('keydown', unlockAudio, true);
        window.removeEventListener('pointermove', handleDragMove);
        stopLightning();
        if (audioContext) { void audioContext.close(); audioContext = null; }
        destroyPortalUi();
        removeCampLayers();
    });
</script>

<style lang="less">
    .zanka-embedded-host { position: fixed; inset: 0; z-index: 10020; pointer-events: none; }
    .zanka-settings-fab {
        position: fixed; top: 88px; left: 18px; width: 38px; height: 38px; border: 1px solid rgba(255,255,255,.20);
        border-radius: 50%; color: #fff; background: rgba(10,14,22,.90); box-shadow: 0 10px 30px rgba(0,0,0,.34);
        backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px); cursor: pointer; pointer-events: auto;
        font: 700 20px/1 -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif; display:flex; align-items:center; justify-content:center;
    }
    .zanka-settings-fab.is-open { opacity: 0; pointer-events: none; }
    .zanka-floating-settings {
        position: fixed; top: 520px; left: 18px; width: min(320px, calc(100vw - 36px)); max-height: calc(100vh - 112px); overflow: auto;
        padding: 12px; box-sizing: border-box; pointer-events: auto; color: #fff; border-radius: 18px;
        background: rgba(17,24,39,.92); border: 1px solid rgba(255,255,255,.16); box-shadow: 0 18px 55px rgba(0,0,0,.42);
        backdrop-filter: blur(18px); -webkit-backdrop-filter: blur(18px);
    }
    .zanka-panel-title { display:flex; align-items:center; justify-content:space-between; gap:12px; font-weight:800; font-size:15px; margin:0 0 8px; }
    .zanka-drag-handle { cursor: grab; touch-action: none; user-select: none; }
    .zanka-drag-handle:active { cursor: grabbing; }
    :global(html.zanka-is-dragging), :global(html.zanka-is-dragging *) { cursor: grabbing !important; user-select: none !important; }
    .zanka-panel-title button { border:0; background:transparent; color:#fff; opacity:.75; font-size:22px; line-height:1; padding:2px 4px; cursor:pointer; border-radius:8px; }
    .zanka-panel-title button:hover { opacity:1; background:rgba(255,255,255,.10); }
    .zanka-panel { padding-top: 6px; }
    .status-row { display:flex; align-items:center; gap:8px; margin:8px 0 10px; font-size:12px; opacity:.92; }
    .online,.offline { width:9px; height:9px; border-radius:50%; flex:0 0 auto; }
    .online { background:#22c55e; box-shadow:0 0 8px #22c55e; }
    .offline { background:#ef4444; box-shadow:0 0 8px #ef4444; }
    .icon-button { margin-left:auto; border:0; background:rgba(255,255,255,.12); color:#fff; border-radius:7px; padding:5px 8px; cursor:pointer; }
    .sound-tests { display:flex; align-items:center; gap:6px; margin:4px 0 9px; font-size:11px; opacity:.9; }
    .sound-tests button,.notification-tests button { min-width:30px; padding:5px 8px; border:1px solid rgba(255,255,255,.2); border-radius:7px; color:#fff; background:rgba(255,255,255,.10); cursor:pointer; }
    .camp-actions { display:grid; grid-template-columns:1fr; gap:7px; }
    .action { width:100%; padding:10px; border-radius:8px; border:1px solid rgba(255,255,255,.22); background:rgba(15,23,42,.82); color:#fff; font-weight:700; cursor:pointer; }
    .section-title { margin:14px 0 7px; font-size:12px; font-weight:700; opacity:.85; }
    .notification-tests { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:6px; }
    .notification-tests button { font-size:11px; }
    .updated { margin-top:10px; font-size:10px; opacity:.62; }
</style>
