// StreamFlix IPTV — Samsung Tizen Smart TV App Logic
(function () {
    const KEYS = {
        profiles: "sf_tv_profiles_v1",
        progress: "sf_tv_progress_v1",
        favMovies: "sf_tv_fav_movies_v1",
        favSeries: "sf_tv_fav_series_v1",
        favChannels: "sf_tv_fav_channels_v1",
        osKey: "sf_tv_os_key_v1",
        geminiKey: "sf_tv_gemini_key_v1",
        subLang: "sf_tv_sub_lang_v1",
        curation: "sf_tv_curation_v2",
        firebaseUrl: "sf_tv_firebase_url_v1"
    };

    const SUB_LANGS = {
        en: { code: "en", label: "English", flag: "🇺🇸" },
        ar: { code: "ar", label: "العربية", flag: "🇪🇬" },
        es: { code: "es", label: "Español", flag: "🇪🇸" }
    };

    const state = {
        creds: null,
        authInfo: null,
        tab: "home",
        search: "",
        liveCats: [], live: [],
        vodCats: [], movies: [],
        serCats: [], series: [],
        normLive: [], normMovies: [], normSeries: [],
        selectedCat: { movies: null, series: null, live: null },
        progress: JSON.parse(localStorage.getItem(KEYS.progress) || "{}"),
        favMovies: new Set(JSON.parse(localStorage.getItem(KEYS.favMovies) || "[]")),
        favSeries: new Set(JSON.parse(localStorage.getItem(KEYS.favSeries) || "[]")),
        favChannels: new Set(JSON.parse(localStorage.getItem(KEYS.favChannels) || "[]")),
        curation: {
            trendingMovies: [],
            trendingSeries: [],
            trendingAnime: [],
            forYouMovies: [],
            forYouSeries: [],
            forYouReason: "Top Picks for You ✨",
            isLoading: false
        },
        subSettings: {
            osKey: localStorage.getItem(KEYS.osKey) || "",
            geminiKey: localStorage.getItem(KEYS.geminiKey) || "",
            lang: localStorage.getItem(KEYS.subLang) || "en"
        },
        cloudSync: {
            url: localStorage.getItem(KEYS.firebaseUrl) || "",
            isSyncing: false,
            status: "",
            pushTimer: null
        },
        subCache: {},
        player: {
            item: null,
            current: 0,
            total: 0,
            isPaused: false,
            usingAVPlay: false,
            timer: null,
            hudTimer: null,
            consecutiveAuto: 0,
            sleepInterval: null,
            subCues: [],
            subActive: false
        }
    };

    // Register Samsung TV Remote Keys
    if (window.tizen && tizen.tvinputdevice) {
        ["MediaPlayPause", "MediaPlay", "MediaPause", "MediaFastForward", "MediaRewind", "ChannelUp", "ChannelDown"].forEach(k => {
            try { tizen.tvinputdevice.registerKey(k); } catch (e) {}
        });
    }

    function escapeHTML(str) {
        return String(str || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }

    function normalizeArabic(text) {
        return (text || "")
            .toLowerCase()
            .trim()
            .replace(/[\u064B-\u065F\u0640\u0670]/g, "")
            .replace(/[آأإٱ]/g, "ا")
            .replace(/ى/g, "ي")
            .replace(/ة/g, "ه");
    }

    function looseMatchKey(text) {
        return normalizeArabic(text)
            .replace(/[^a-z0-9\u0600-\u06ff]+/g, " ")
            .replace(/\s+/g, " ")
            .trim();
    }

    function formatTime(sec) {
        sec = Math.max(0, Math.floor(sec || 0));
        const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
        const pad = n => String(n).padStart(2, "0");
        return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
    }

    function apiURL(action, extra = "") {
        return `${state.creds.host}/player_api.php?username=${encodeURIComponent(state.creds.username)}&password=${encodeURIComponent(state.creds.password)}${action ? "&action=" + action : ""}${extra}`;
    }

    async function fetchJSON(url) {
        const res = await fetch(url);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
    }

    function cleanMediaTitle(raw, kind) {
        let text = String(raw || "");
        if (kind === "episode") {
            text = text.split(" • ")[0].split(" — ")[0];
        }
        const yearMatch = text.match(/\b(19\d{2}|20\d{2})\b/);
        const year = yearMatch ? Number(yearMatch[1]) : null;
        text = text
            .replace(/^(?:EN|AR|TR|FR|ES|DE|IT|ANIME|VIP|4K|UHD|FHD|HD|SD|MULTI|SUB|DUB|NETFLIX|APPLE|HBO|DISNEY)\s*[-:|]+\s*/i, "")
            .replace(/\[[^\]]*\]/g, " ")
            .replace(/\((?:19\d{2}|20\d{2}|4K|HD|FHD|UHD|SD|EN|AR|TR|FR|ES|MULTI|DUB|SUB)\)/gi, " ")
            .replace(/\b(?:4K|UHD|FHD|1080p|720p|480p|WEB-DL|WEBRip|BluRay|HDRip|DVDRip|x264|x265|HEVC|H\.264|H\.265)\b/gi, " ")
            .replace(/\bS\d+\s*E\d+\b/gi, " ")
            .replace(/[.|_]+/g, " ")
            .replace(/\s+/g, " ")
            .trim();
        return { query: text || raw, year };
    }

    function bindTVInput(inp) {
        if (!inp) return;
        inp.classList.add("tv-focusable");
        inp.readOnly = true;
        inp.addEventListener("blur", () => { inp.readOnly = true; });
    }

    // MARK: - Login & Profiles
    function renderSavedProfiles() {
        const list = JSON.parse(localStorage.getItem(KEYS.profiles) || "[]");
        const el = document.getElementById("saved-profiles");
        el.innerHTML = "";
        list.forEach((p, idx) => {
            const row = document.createElement("div");
            row.className = "profile-row";
            row.innerHTML = `<span><strong>${p.profileName}</strong> • ${p.username}</span>`;
            const btns = document.createElement("div");
            const bOpen = document.createElement("button");
            bOpen.className = "btn-primary tv-focusable";
            bOpen.textContent = "Open";
            bOpen.onclick = () => signIn(p);
            const bDel = document.createElement("button");
            bDel.className = "btn-secondary tv-focusable";
            bDel.style.marginLeft = "10px";
            bDel.textContent = "Delete";
            bDel.onclick = () => {
                list.splice(idx, 1);
                localStorage.setItem(KEYS.profiles, JSON.stringify(list));
                renderSavedProfiles();
            };
            btns.append(bOpen, bDel);
            row.appendChild(btns);
            el.appendChild(row);
        });
    }

    async function signIn(creds) {
        const errEl = document.getElementById("login-error");
        errEl.textContent = "Connecting...";
        let host = creds.host.trim().replace(/\/+$/, "");
        if (!/^https?:\/\//i.test(host)) host = "http://" + host;
        state.creds = { ...creds, host };
        try {
            const auth = await fetchJSON(apiURL(""));
            if (!auth.user_info || String(auth.user_info.status).toLowerCase() !== "active") {
                throw new Error("Account inactive");
            }
            state.authInfo = auth;
            const profiles = JSON.parse(localStorage.getItem(KEYS.profiles) || "[]").filter(p => !(p.host === state.creds.host && p.username === state.creds.username));
            profiles.unshift(state.creds);
            localStorage.setItem(KEYS.profiles, JSON.stringify(profiles));

            document.getElementById("login-screen").classList.remove("active");
            document.getElementById("main-screen").classList.add("active");
            await loadCatalog();
            focusFirstInScope();
        } catch (e) {
            errEl.textContent = "Login failed: " + e.message;
        }
    }

    async function loadCatalog() {
        const area = document.getElementById("content-area");
        area.innerHTML = "<h2 style='margin-top:40px;'>Loading your library...</h2>";
        const [lc, l, vc, v, sc, s] = await Promise.allSettled([
            fetchJSON(apiURL("get_live_categories")),
            fetchJSON(apiURL("get_live_streams")),
            fetchJSON(apiURL("get_vod_categories")),
            fetchJSON(apiURL("get_vod_streams")),
            fetchJSON(apiURL("get_series_categories")),
            fetchJSON(apiURL("get_series"))
        ]);
        state.liveCats = lc.value || [];
        state.live = l.value || [];
        state.vodCats = vc.value || [];
        state.movies = v.value || [];
        state.serCats = sc.value || [];
        state.series = s.value || [];

        // Pre-normalize once for instant search & matching
        state.normLive = state.live.map(x => ({ item: x, norm: normalizeArabic(x.name), loose: looseMatchKey(x.name) }));
        state.normMovies = state.movies.map(x => ({ item: x, norm: normalizeArabic(x.name), loose: looseMatchKey(x.name) }));
        state.normSeries = state.series.map(x => ({ item: x, norm: normalizeArabic(x.name), loose: looseMatchKey(x.name) }));

        renderTab();
        loadLiveCuration(false);
        cloudPullAndMerge();
    }

    // MARK: - Live IMDb/Cinemeta & AniList Trending + Personalized Picks (Free, Zero Key)
    function matchCatalog(titles, normList, idField, imgField, limit) {
        const seen = new Set();
        const out = [];
        for (const raw of titles || []) {
            const q = normalizeArabic(raw);
            const lq = looseMatchKey(raw);
            if (q.length < 2) continue;
            const hit = normList.find(x => x.norm === q || x.loose === lq)
                || normList.find(x => (x.norm.includes(q) || x.loose.includes(lq)) && x.item[imgField]);
            if (hit && !seen.has(hit.item[idField])) {
                seen.add(hit.item[idField]);
                out.push(hit.item);
                if (out.length >= limit) break;
            }
        }
        return out;
    }

    async function fetchCinemeta(type, catalog) {
        try {
            const res = await fetch(`https://v3-cinemeta.strem.io/catalog/${type}/${catalog}.json`);
            if (!res.ok) return [];
            const data = await res.json();
            return (data.metas || []).map(m => (m.name || "").trim()).filter(Boolean);
        } catch (e) { return []; }
    }

    async function fetchAniList(query, variables) {
        try {
            const res = await fetch("https://graphql.anilist.co", {
                method: "POST",
                headers: { "Content-Type": "application/json", "Accept": "application/json" },
                body: JSON.stringify(variables ? { query, variables } : { query })
            });
            if (!res.ok) return null;
            return res.json();
        } catch (e) { return null; }
    }

    async function loadLiveCuration(force) {
        if (!state.movies.length && !state.series.length) return;
        const cachedRaw = !force ? localStorage.getItem(KEYS.curation) : null;
        if (cachedRaw) {
            try {
                const cached = JSON.parse(cachedRaw);
                if (Date.now() - (cached.fetchedAt || 0) < 6 * 3600 * 1000) {
                    applyCurationTitles(cached);
                    return;
                }
            } catch (e) {}
        }

        state.curation.isLoading = true;
        if (state.tab === "home") renderTab();

        const recentRec = Object.values(state.progress).sort((a, b) => b.updatedAt - a.updatedAt)[0];
        const favSer = state.series.find(s => state.favSeries.has(s.series_id));
        const anchorRaw = (recentRec && recentRec.item && recentRec.item.title) || (favSer && favSer.name) || "";
        const anchorClean = anchorRaw ? cleanMediaTitle(anchorRaw, "episode").query : "";

        const [topM, topS, ratedM, aniTrend, aniSim] = await Promise.all([
            fetchCinemeta("movie", "top"),
            fetchCinemeta("series", "top"),
            fetchCinemeta("movie", "imdbRating"),
            fetchAniList(`query { Page(page: 1, perPage: 25) { media(type: ANIME, sort: TRENDING_DESC, isAdult: false) { title { english romaji } } } }`),
            anchorClean ? fetchAniList(`query ($search: String) { Media(search: $search, type: ANIME) { recommendations(sort: RATING_DESC, perPage: 20) { nodes { mediaRecommendation { title { english romaji } } } } } }`, { search: anchorClean }) : Promise.resolve(null)
        ]);

        const topAnime = ((aniTrend && aniTrend.data && aniTrend.data.Page && aniTrend.data.Page.media) || [])
            .map(m => (m.title && (m.title.english || m.title.romaji)) || "").filter(Boolean);
        const simAnime = ((aniSim && aniSim.data && aniSim.data.Media && aniSim.data.Media.recommendations && aniSim.data.Media.recommendations.nodes) || [])
            .map(n => n.mediaRecommendation && n.mediaRecommendation.title && (n.mediaRecommendation.title.english || n.mediaRecommendation.title.romaji)).filter(Boolean);

        const payload = {
            trendingMovies: topM,
            trendingSeries: topS,
            trendingAnime: topAnime,
            forYouMovies: (ratedM.length ? ratedM : topM).slice().sort(() => Math.random() - 0.5).slice(0, 18),
            forYouSeries: simAnime.length ? simAnime : topS.slice().sort(() => Math.random() - 0.5).slice(0, 18),
            forYouReason: (anchorClean && simAnime.length) ? `Similar to ${anchorClean} ✨` : "Top IMDb & Popular Picks ✨",
            fetchedAt: Date.now()
        };

        if (topM.length || topS.length || topAnime.length) {
            localStorage.setItem(KEYS.curation, JSON.stringify(payload));
        }
        state.curation.isLoading = false;
        applyCurationTitles(payload);
    }

    function applyCurationTitles(payload) {
        state.curation.trendingMovies = matchCatalog(payload.trendingMovies, state.normMovies, "stream_id", "stream_icon", 20);
        state.curation.trendingSeries = matchCatalog(payload.trendingSeries, state.normSeries, "series_id", "cover", 20);
        state.curation.trendingAnime = matchCatalog(payload.trendingAnime, state.normSeries, "series_id", "cover", 20);
        state.curation.forYouMovies = matchCatalog(payload.forYouMovies, state.normMovies, "stream_id", "stream_icon", 18);
        state.curation.forYouSeries = matchCatalog(payload.forYouSeries, state.normSeries, "series_id", "cover", 18);
        state.curation.forYouReason = payload.forYouReason || "Top Picks for You ✨";
        if (state.tab === "home" && !state.search.trim()) {
            renderTab();
        }
    }

    // MARK: - Progress Helpers (Series-Aware Continue Watching)
    function seriesKeyForItem(item) {
        if (!item || item.kind !== "episode") return item ? item.id : "";
        if (item.seriesId) return `series-${item.seriesId}`;
        const base = String(item.title || "").split(" • ")[0].trim().toLowerCase();
        return base ? `series-name-${base}` : item.id;
    }

    function getContinueWatchingList() {
        const sorted = Object.values(state.progress)
            .filter(r => r.item && r.item.kind !== "live" && r.position >= 5 && r.duration > 0 && (r.position / r.duration) < 0.93)
            .sort((a, b) => b.updatedAt - a.updatedAt);
        const seen = new Set();
        const unique = [];
        for (const rec of sorted) {
            const key = seriesKeyForItem(rec.item);
            if (!seen.has(key)) {
                seen.add(key);
                unique.push(rec);
            }
        }
        return unique;
    }

    function getLatestSeriesRecord(seriesId) {
        return Object.values(state.progress)
            .filter(r => r.item && r.item.kind === "episode" && String(r.item.seriesId) === String(seriesId))
            .sort((a, b) => b.updatedAt - a.updatedAt)[0] || null;
    }

    // MARK: - Cloud Sync (Firebase Realtime Database REST — Compatible with iPhone/iPad/Mac)
    function getCloudEndpoint() {
        const raw = (state.cloudSync.url || "").trim().replace(/\/+$/, "");
        if (!/^https:\/\//i.test(raw) || !state.creds || !state.creds.username) return null;
        const parts = String(state.creds.username).trim().split(/[.#$\[\]\/ ]+/).filter(Boolean);
        const safeKey = parts.length ? parts.join("_") : "default_user";
        return `${raw}/streamflix/${safeKey}.json`;
    }

    function toLocalProgressId(id) {
        const s = String(id || "");
        return s.startsWith("episode-") ? "ep-" + s.slice(8) : s;
    }

    function toRemoteProgressId(id) {
        const s = String(id || "");
        return s.startsWith("ep-") ? "episode-" + s.slice(3) : s;
    }

    function toLocalRecord(remoteRec) {
        if (!remoteRec || !remoteRec.item) return null;
        const localId = toLocalProgressId(remoteRec.id || remoteRec.item.id);
        const it = remoteRec.item;
        return {
            item: {
                id: localId,
                title: it.title || "",
                subtitle: it.subtitle || "",
                artwork: it.artworkURL || it.artwork || "",
                url: it.streamURL || it.url || "",
                kind: it.kind || "movie",
                seriesId: it.seriesId != null ? Number(it.seriesId) : undefined,
                seasonNumber: it.seasonNumber != null ? Number(it.seasonNumber) : undefined,
                episodeNumber: it.episodeNumber != null ? Number(it.episodeNumber) : undefined
            },
            position: Number(remoteRec.positionSeconds != null ? remoteRec.positionSeconds : (remoteRec.position || 0)),
            duration: Number(remoteRec.durationSeconds != null ? remoteRec.durationSeconds : (remoteRec.duration || 0)),
            updatedAt: typeof remoteRec.updatedAt === "number" ? remoteRec.updatedAt : (Date.parse(remoteRec.updatedAt) || 0)
        };
    }

    function toRemoteRecord(localRec) {
        if (!localRec || !localRec.item || !localRec.item.url) return null;
        const remoteId = toRemoteProgressId(localRec.item.id);
        const it = localRec.item;
        const outItem = {
            id: remoteId,
            title: it.title || "",
            subtitle: it.subtitle || null,
            artworkURL: it.artwork || null,
            streamURL: it.url || "",
            kind: it.kind || "movie"
        };
        if (it.seriesId != null) outItem.seriesId = Number(it.seriesId);
        if (it.seasonNumber != null) outItem.seasonNumber = Number(it.seasonNumber);
        if (it.episodeNumber != null) outItem.episodeNumber = Number(it.episodeNumber);
        return {
            id: remoteId,
            item: outItem,
            positionSeconds: Number(localRec.position || 0),
            durationSeconds: Number(localRec.duration || 0),
            updatedAt: new Date(localRec.updatedAt || Date.now()).toISOString()
        };
    }

    function mergeRemoteProgress(remoteMap) {
        let changed = false;
        for (const key of Object.keys(remoteMap || {})) {
            const rec = toLocalRecord(remoteMap[key]);
            if (!rec || !rec.item || !rec.duration) continue;
            const localId = rec.item.id;
            const local = state.progress[localId];
            const isDone = rec.duration > 0 && (rec.position / rec.duration) >= 0.93;
            if (local) {
                if (rec.updatedAt > (local.updatedAt || 0)) {
                    state.progress[localId] = rec;
                    changed = true;
                }
            } else if (!isDone || rec.item.kind === "episode") {
                state.progress[localId] = rec;
                changed = true;
            }
        }
        const newestBySeries = {};
        for (const rec of Object.values(state.progress)) {
            if (!rec.item || rec.item.kind !== "episode") continue;
            const sk = seriesKeyForItem(rec.item);
            if (!newestBySeries[sk] || rec.updatedAt > newestBySeries[sk].updatedAt) {
                newestBySeries[sk] = rec;
            }
        }
        const keepIds = new Set(Object.values(newestBySeries).map(r => r.item.id));
        for (const id of Object.keys(state.progress)) {
            const rec = state.progress[id];
            if (rec && rec.item && rec.item.kind === "episode" && !keepIds.has(id)) {
                delete state.progress[id];
                changed = true;
            }
        }
        if (changed) localStorage.setItem(KEYS.progress, JSON.stringify(state.progress));
        return changed;
    }

    async function cloudPullAndMerge() {
        const url = getCloudEndpoint();
        if (!url) return false;
        state.cloudSync.isSyncing = true;
        state.cloudSync.status = "Syncing...";
        try {
            const res = await fetch(url);
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const text = (await res.text()).trim();
            if (!text || text === "null") {
                await cloudPushNow();
                state.cloudSync.status = "Synced ✓";
                return true;
            }
            const remote = JSON.parse(text);
            const progChanged = mergeRemoteProgress(remote.watchProgress || {});
            let favChanged = false;
            (remote.favoriteSeriesIds || []).forEach(id => { const n = Number(id); if (!state.favSeries.has(n)) { state.favSeries.add(n); favChanged = true; } });
            (remote.favoriteMovieIds || []).forEach(id => { const n = Number(id); if (!state.favMovies.has(n)) { state.favMovies.add(n); favChanged = true; } });
            (remote.favoriteChannelIds || []).forEach(id => { const n = Number(id); if (!state.favChannels.has(n)) { state.favChannels.add(n); favChanged = true; } });
            if (favChanged) {
                localStorage.setItem(KEYS.favSeries, JSON.stringify([...state.favSeries]));
                localStorage.setItem(KEYS.favMovies, JSON.stringify([...state.favMovies]));
                localStorage.setItem(KEYS.favChannels, JSON.stringify([...state.favChannels]));
            }
            state.cloudSync.status = "Synced ✓";
            if ((progChanged || favChanged) && state.tab === "home" && !state.search.trim()) renderTab();
            return true;
        } catch (e) {
            state.cloudSync.status = "Sync error: " + e.message;
            return false;
        } finally {
            state.cloudSync.isSyncing = false;
        }
    }

    async function cloudPushNow() {
        const url = getCloudEndpoint();
        if (!url) return;
        const remoteProgress = {};
        for (const rec of Object.values(state.progress)) {
            const r = toRemoteRecord(rec);
            if (r) remoteProgress[r.id] = r;
        }
        const payload = {
            watchProgress: remoteProgress,
            favoriteSeriesIds: [...state.favSeries].map(Number).sort((a, b) => a - b),
            favoriteMovieIds: [...state.favMovies].map(Number).sort((a, b) => a - b),
            favoriteChannelIds: [...state.favChannels].map(Number).sort((a, b) => a - b),
            updatedAt: new Date().toISOString()
        };
        try {
            const res = await fetch(url, {
                method: "PUT",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(payload)
            });
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            state.cloudSync.status = "Synced ✓";
        } catch (e) {
            state.cloudSync.status = "Sync error: " + e.message;
        }
    }

    function scheduleCloudPush() {
        if (!getCloudEndpoint()) return;
        clearTimeout(state.cloudSync.pushTimer);
        state.cloudSync.pushTimer = setTimeout(() => cloudPushNow(), 1500);
    }

    // MARK: - Rendering Tabs
    function posterCard(title, img, progressFrac, onClick) {
        const btn = document.createElement("button");
        btn.className = "poster-card tv-focusable";
        btn.onclick = onClick;
        btn.innerHTML = `<img src="${escapeHTML(img || "")}" loading="lazy" onerror="this.style.opacity=0.2">` +
            (progressFrac ? `<div class="progress-bar-mini"><div style="width:${Math.round(progressFrac * 100)}%"></div></div>` : "") +
            `<div class="poster-title" dir="auto">${escapeHTML(title)}</div>`;
        return btn;
    }

    function renderTab() {
        const area = document.getElementById("content-area");
        area.innerHTML = "";

        if (state.search.trim()) {
            const q = normalizeArabic(state.search.trim());
            const fSeries = state.normSeries.filter(x => x.norm.includes(q)).slice(0, 35).map(x => x.item);
            const fMovies = state.normMovies.filter(x => x.norm.includes(q)).slice(0, 35).map(x => x.item);
            const fLive = state.normLive.filter(x => x.norm.includes(q)).slice(0, 25).map(x => x.item);
            if (fSeries.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Series (${fSeries.length})</div>`);
                const g = document.createElement("div"); g.className = "grid-view";
                fSeries.forEach(s => g.appendChild(posterCard(s.name, s.cover, 0, () => openSeriesModal(s))));
                area.appendChild(g);
            }
            if (fMovies.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Movies (${fMovies.length})</div>`);
                const g = document.createElement("div"); g.className = "grid-view";
                fMovies.forEach(m => g.appendChild(posterCard(m.name, m.stream_icon, 0, () => playMovie(m))));
                area.appendChild(g);
            }
            if (fLive.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Live Channels (${fLive.length})</div>`);
                const list = document.createElement("div"); list.className = "channel-list";
                fLive.forEach(ch => list.appendChild(channelRow(ch, fLive)));
                area.appendChild(list);
            }
            return;
        }

        if (state.tab === "home") {
            const hero = state.curation.trendingMovies[0] || state.movies.find(m => m.stream_icon) || state.movies[0];
            if (hero) {
                const hb = document.createElement("div");
                hb.className = "hero-banner";
                hb.innerHTML = `<img class="hero-backdrop" src="${escapeHTML(hero.stream_icon || "")}" onerror="this.style.display='none'"><div class="hero-overlay"><span class="hero-badge">FEATURED</span><h2 dir="auto">${escapeHTML(hero.name)}</h2><div class="hero-actions"></div></div><img class="hero-poster" src="${escapeHTML(hero.stream_icon || "")}" onerror="this.style.display='none'">`;
                const actions = hb.querySelector(".hero-actions");

                const playBtn = document.createElement("button");
                playBtn.className = "btn-primary tv-focusable";
                playBtn.textContent = "▶ Play";
                playBtn.onclick = () => playMovie(hero);

                const refreshBtn = document.createElement("button");
                refreshBtn.className = "btn-secondary tv-focusable";
                refreshBtn.textContent = state.curation.isLoading ? "⏳ Loading Picks..." : "✨ Refresh Top Picks";
                refreshBtn.onclick = () => loadLiveCuration(true);

                actions.append(playBtn, refreshBtn);
                area.appendChild(hb);
            }

            // Continue Watching (deduplicated per series)
            const cw = getContinueWatchingList();
            if (cw.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Continue Watching</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                cw.forEach(r => row.appendChild(posterCard(r.item.title, r.item.artwork, r.position / r.duration, () => startPlayback(r.item))));
                area.appendChild(row);
            }

            // Personalized Recommendations (Movies & Series)
            if (state.curation.forYouMovies.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">${state.curation.forYouReason}</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                state.curation.forYouMovies.forEach(m => row.appendChild(posterCard(m.name, m.stream_icon, 0, () => playMovie(m))));
                area.appendChild(row);
            }
            if (state.curation.forYouSeries.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Series Picks for You ✨</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                state.curation.forYouSeries.forEach(s => row.appendChild(posterCard(s.name, s.cover, 0, () => openSeriesModal(s))));
                area.appendChild(row);
            }

            // Favorite Series
            const favSer = state.series.filter(s => state.favSeries.has(s.series_id));
            if (favSer.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">My List — Series ❤️</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                favSer.forEach(s => row.appendChild(posterCard(s.name, s.cover, 0, () => openSeriesModal(s))));
                area.appendChild(row);
            }

            // Favorite Movies
            const favMov = state.movies.filter(m => state.favMovies.has(m.stream_id));
            if (favMov.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">My List — Movies ❤️</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                favMov.forEach(m => row.appendChild(posterCard(m.name, m.stream_icon, 0, () => playMovie(m))));
                area.appendChild(row);
            }

            // Trending Movies
            const trendingM = state.curation.trendingMovies.length ? state.curation.trendingMovies : state.movies.filter(m => m.stream_icon).slice(0, 20);
            if (trendingM.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Trending Movies 🔥</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                trendingM.forEach(m => row.appendChild(posterCard(m.name, m.stream_icon, 0, () => playMovie(m))));
                area.appendChild(row);
            }

            // Trending Series
            const trendingS = state.curation.trendingSeries.length ? state.curation.trendingSeries : state.series.filter(s => s.cover).slice(0, 20);
            if (trendingS.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Trending Series ⭐</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                trendingS.forEach(s => row.appendChild(posterCard(s.name, s.cover, 0, () => openSeriesModal(s))));
                area.appendChild(row);
            }

            // Trending Anime
            if (state.curation.trendingAnime.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Trending Anime 🎌</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                state.curation.trendingAnime.forEach(s => row.appendChild(posterCard(s.name, s.cover, 0, () => openSeriesModal(s))));
                area.appendChild(row);
            }
        } else if (state.tab === "movies") {
            renderSplitCatalog(area, state.vodCats, state.selectedCat.movies, id => { state.selectedCat.movies = id; renderTab(); }, mainPane => {
                const items = (state.selectedCat.movies ? state.movies.filter(m => String(m.category_id) === String(state.selectedCat.movies)) : state.movies).slice(0, 140);
                const g = document.createElement("div"); g.className = "grid-view-sidebar";
                items.forEach(m => g.appendChild(posterCard(m.name, m.stream_icon, 0, () => playMovie(m))));
                mainPane.appendChild(g);
            });
        } else if (state.tab === "series") {
            renderSplitCatalog(area, state.serCats, state.selectedCat.series, id => { state.selectedCat.series = id; renderTab(); }, mainPane => {
                const items = (state.selectedCat.series ? state.series.filter(s => String(s.category_id) === String(state.selectedCat.series)) : state.series).slice(0, 140);
                const g = document.createElement("div"); g.className = "grid-view-sidebar";
                items.forEach(s => g.appendChild(posterCard(s.name, s.cover, 0, () => openSeriesModal(s))));
                mainPane.appendChild(g);
            });
        } else if (state.tab === "live") {
            renderSplitCatalog(area, state.liveCats, state.selectedCat.live, id => { state.selectedCat.live = id; renderTab(); }, mainPane => {
                mainPane.style.padding = "0";
                mainPane.style.overflow = "hidden";
                const items = (state.selectedCat.live ? state.live.filter(c => String(c.category_id) === String(state.selectedCat.live)) : state.live).slice(0, 240);
                renderLiveDishGuide(mainPane, items);
            });
        } else if (state.tab === "account") {
            const ui = (state.authInfo && state.authInfo.user_info) || {};
            const box = document.createElement("div");
            box.className = "account-box";
            box.innerHTML = `<div class="section-title">Account &amp; Subtitles</div>
                <p style="font-size:22px;">Profile: <strong>${state.creds.profileName}</strong> • Server: ${state.creds.host}</p>
                <p style="font-size:20px; color:#aaa; margin-bottom:10px;">Connections: ${ui.active_cons || 0} / ${ui.max_connections || 1}</p>`;

            const osInput = document.createElement("input");
            osInput.className = "account-input";
            osInput.type = "password";
            osInput.placeholder = "OpenSubtitles API Key (opensubtitles.com → API Consumers)";
            osInput.value = state.subSettings.osKey;
            osInput.oninput = e => {
                state.subSettings.osKey = e.target.value.trim();
                localStorage.setItem(KEYS.osKey, state.subSettings.osKey);
            };
            bindTVInput(osInput);

            const gemInput = document.createElement("input");
            gemInput.className = "account-input";
            gemInput.type = "password";
            gemInput.placeholder = "Gemini API Key (Optional — for AI Subtitle Translation)";
            gemInput.value = state.subSettings.geminiKey;
            gemInput.oninput = e => {
                state.subSettings.geminiKey = e.target.value.trim();
                localStorage.setItem(KEYS.geminiKey, state.subSettings.geminiKey);
            };
            bindTVInput(gemInput);

            const langBtn = document.createElement("button");
            langBtn.className = "btn-secondary tv-focusable";
            const updateLangBtn = () => {
                const l = SUB_LANGS[state.subSettings.lang] || SUB_LANGS.en;
                langBtn.textContent = `Default Subtitle Language: ${l.flag} ${l.label} (Press OK to switch)`;
            };
            updateLangBtn();
            langBtn.onclick = () => {
                const order = ["en", "ar", "es"];
                const next = order[(order.indexOf(state.subSettings.lang) + 1) % order.length];
                state.subSettings.lang = next;
                localStorage.setItem(KEYS.subLang, next);
                updateLangBtn();
            };

            const fbInput = document.createElement("input");
            fbInput.className = "account-input";
            fbInput.type = "text";
            fbInput.placeholder = "Firebase Realtime Database URL (https://...)";
            fbInput.value = state.cloudSync.url;
            fbInput.oninput = e => {
                state.cloudSync.url = e.target.value.trim();
                localStorage.setItem(KEYS.firebaseUrl, state.cloudSync.url);
            };
            bindTVInput(fbInput);

            const syncBtn = document.createElement("button");
            syncBtn.className = "btn-secondary tv-focusable";
            const updateSyncLabel = () => {
                syncBtn.textContent = state.cloudSync.status
                    ? `☁️ Cloud Sync (${state.cloudSync.status}) — Press OK to Sync Now`
                    : "☁️ Sync Now (iPhone / iPad / TV)";
            };
            updateSyncLabel();
            syncBtn.onclick = async () => {
                syncBtn.textContent = "⏳ Syncing...";
                await cloudPullAndMerge();
                await cloudPushNow();
                updateSyncLabel();
            };

            const refreshLibBtn = document.createElement("button");
            refreshLibBtn.className = "btn-secondary tv-focusable";
            refreshLibBtn.textContent = "🔄 Refresh Library & Top Picks";
            refreshLibBtn.onclick = async () => {
                localStorage.removeItem(KEYS.curation);
                await loadCatalog();
            };

            const outBtn = document.createElement("button");
            outBtn.className = "btn-primary tv-focusable";
            outBtn.textContent = "Sign Out";
            outBtn.onclick = () => {
                document.getElementById("main-screen").classList.remove("active");
                document.getElementById("login-screen").classList.add("active");
                renderSavedProfiles();
            };

            box.append(osInput, gemInput, langBtn, fbInput, syncBtn, refreshLibBtn, outBtn);
            area.appendChild(box);
        }
    }

    function renderSplitCatalog(container, cats, activeId, onCatSelect, renderRightPane) {
        const split = document.createElement("div");
        split.className = "tv-split";

        const sidebar = document.createElement("div");
        sidebar.className = "tv-sidebar";

        const addCat = (id, label) => {
            const b = document.createElement("button");
            const isActive = String(id || "") === String(activeId || "");
            b.className = "cat-item tv-focusable" + (isActive ? " active" : "");
            b.textContent = label;
            b.onclick = () => {
                onCatSelect(id || null);
                setTimeout(() => {
                    const activeBtn = document.querySelector(".tv-sidebar .cat-item.active");
                    if (activeBtn) activeBtn.focus();
                }, 40);
            };
            sidebar.appendChild(b);
        };

        addCat(null, "All Categories");
        cats.forEach(c => addCat(c.category_id, c.category_name));

        const mainPane = document.createElement("div");
        mainPane.className = "tv-main-pane";
        renderRightPane(mainPane);

        split.append(sidebar, mainPane);
        container.appendChild(split);
    }

    function renderLiveDishGuide(container, items) {
        const wrap = document.createElement("div");
        wrap.className = "live-dish-wrap";
        const listPane = document.createElement("div");
        listPane.className = "live-dish-list-pane";
        const preview = document.createElement("div");
        preview.className = "live-dish-preview";
        preview.innerHTML = `<img id="dish-prev-logo" class="live-preview-logo" src="" onerror="this.style.opacity=0.15"><div id="dish-prev-num" class="live-preview-num">CHANNEL 001</div><div id="dish-prev-title" class="live-preview-title">Select a Channel</div><div class="live-remote-hints"><div><strong>OK</strong> : تشغيل القناة ملء الشاشة</div><div><strong>▲ ▼</strong> : تقليب القنوات زي الدش</div><div><strong>OK</strong> أثناء المشاهدة : فتح قائمة القنوات</div></div>`;
        const updatePreview = (ch, num) => {
            const logo = preview.querySelector("#dish-prev-logo");
            logo.style.opacity = ch.stream_icon ? "1" : "0.15";
            logo.src = ch.stream_icon || "";
            preview.querySelector("#dish-prev-num").textContent = `CHANNEL ${String(num).padStart(3, "0")}`;
            preview.querySelector("#dish-prev-title").textContent = ch.name;
        };
        items.forEach((ch, idx) => {
            const num = idx + 1;
            const btn = document.createElement("button");
            btn.className = "live-dish-row tv-focusable";
            btn.innerHTML = `<span class="live-num">${String(num).padStart(3, "0")}</span><img src="${escapeHTML(ch.stream_icon || "")}" style="width:44px;height:32px;object-fit:contain;flex-shrink:0;" onerror="this.style.opacity=0.2"><span class="live-name" dir="auto">${escapeHTML(ch.name)}</span>`;
            btn.onfocus = () => updatePreview(ch, num);
            btn.onclick = () => playChannel(ch, items);
            listPane.appendChild(btn);
        });
        if (items.length) updatePreview(items[0], 1);
        wrap.append(listPane, preview);
        container.appendChild(wrap);
    }

    function channelRow(ch, list) {
        const btn = document.createElement("button");
        btn.className = "channel-row tv-focusable";
        btn.innerHTML = `<img src="${ch.stream_icon || ""}" onerror="this.style.opacity=0.2"><span>${ch.name}</span>`;
        btn.onclick = () => playChannel(ch, list);
        return btn;
    }

    // MARK: - Series Modal (With Resume & Episode Progress)
    async function openSeriesModal(series) {
        const modal = document.getElementById("series-modal");
        modal.classList.remove("hidden");
        document.getElementById("series-modal-title").textContent = series.name;
        document.getElementById("series-modal-plot").textContent = series.plot || "";

        const lastRec = getLatestSeriesRecord(series.series_id);
        const resumeBtn = document.getElementById("btn-resume-series");
        if (lastRec) {
            const sNum = lastRec.item.seasonNumber || 1;
            const eNum = lastRec.item.episodeNumber || 1;
            const completed = lastRec.duration > 0 && (lastRec.position / lastRec.duration) >= 0.93;
            resumeBtn.textContent = completed ? `▶ Last Watched S${sNum}:E${eNum}` : `▶ Resume S${sNum}:E${eNum}`;
            resumeBtn.classList.remove("hidden");
            resumeBtn.onclick = () => {
                modal.classList.add("hidden");
                startPlayback(lastRec.item);
            };
        } else {
            resumeBtn.classList.add("hidden");
        }

        const favBtn = document.getElementById("btn-fav-series");
        const updateFavBtn = () => favBtn.textContent = state.favSeries.has(series.series_id) ? "♥ In My List" : "♡ My List";
        updateFavBtn();
        favBtn.onclick = () => {
            if (state.favSeries.has(series.series_id)) state.favSeries.delete(series.series_id);
            else state.favSeries.add(series.series_id);
            localStorage.setItem(KEYS.favSeries, JSON.stringify([...state.favSeries]));
            updateFavBtn();
            scheduleCloudPush();
        };
        document.getElementById("btn-close-series").onclick = () => modal.classList.add("hidden");

        const epBox = document.getElementById("episode-list");
        const sTabs = document.getElementById("season-tabs");
        epBox.innerHTML = "<p>Loading episodes...</p>";
        sTabs.innerHTML = "";

        try {
            const info = await fetchJSON(apiURL("get_series_info", `&series_id=${series.series_id}`));
            const seasons = Object.keys(info.episodes || {}).sort((a, b) => Number(a) - Number(b));
            function showSeason(sKey) {
                Array.from(sTabs.children).forEach(btn => btn.classList.toggle("active", btn.dataset.season === String(sKey)));
                const eps = (info.episodes[sKey] || []).slice().sort((a, b) => a.episode_num - b.episode_num);
                epBox.innerHTML = "";
                eps.forEach((ep, i) => {
                    const row = document.createElement("button");
                    const epProg = state.progress[`ep-${ep.id}`];
                    const isLast = lastRec && lastRec.item && lastRec.item.id === `ep-${ep.id}`;
                    const isDone = epProg && epProg.duration > 0 && (epProg.position / epProg.duration) >= 0.93;
                    const epTitle = ep.title || `Episode ${ep.episode_num}`;
                    row.className = "channel-row tv-focusable" + (isLast ? " active-cat" : "");
                    const badgeHTML = isLast ? `<span class="ep-badge">${isDone ? "Watched" : "Continue"}</span>` : "";
                    row.innerHTML = `<span dir="auto">▶ S${sKey}:E${ep.episode_num} — ${escapeHTML(epTitle)}</span>${badgeHTML}`;
                    row.onclick = () => {
                        modal.classList.add("hidden");
                        const ext = ep.container_extension || "mp4";
                        const nextEp = eps[i + 1] ? {
                            id: `ep-${eps[i + 1].id}`,
                            title: `${series.name} • S${sKey}:E${eps[i + 1].episode_num}`,
                            subtitle: eps[i + 1].title,
                            artwork: series.cover,
                            kind: "episode",
                            seriesId: series.series_id,
                            seasonNumber: Number(sKey),
                            episodeNumber: eps[i + 1].episode_num,
                            url: `${state.creds.host}/series/${encodeURIComponent(state.creds.username)}/${encodeURIComponent(state.creds.password)}/${eps[i + 1].id}.${eps[i + 1].container_extension || "mp4"}`
                        } : null;
                        startPlayback({
                            id: `ep-${ep.id}`,
                            title: `${series.name} • S${sKey}:E${ep.episode_num}`,
                            subtitle: ep.title,
                            artwork: series.cover,
                            kind: "episode",
                            seriesId: series.series_id,
                            seasonNumber: Number(sKey),
                            episodeNumber: ep.episode_num,
                            url: `${state.creds.host}/series/${encodeURIComponent(state.creds.username)}/${encodeURIComponent(state.creds.password)}/${ep.id}.${ext}`,
                            nextItem: nextEp
                        });
                    };
                    epBox.appendChild(row);
                });
            }
            seasons.forEach(sKey => {
                const b = document.createElement("button");
                b.className = "btn-secondary tv-focusable";
                b.dataset.season = String(sKey);
                b.textContent = `Season ${sKey}`;
                b.onclick = () => showSeason(sKey);
                sTabs.appendChild(b);
            });
            const initialSeason = (lastRec && lastRec.item && lastRec.item.seasonNumber && seasons.includes(String(lastRec.item.seasonNumber)))
                ? String(lastRec.item.seasonNumber)
                : seasons[0];
            if (initialSeason) showSeason(initialSeason);
            focusFirstInScope();
        } catch (e) {
            epBox.innerHTML = "<p>Could not load episodes.</p>";
        }
    }

    // MARK: - OpenSubtitles API + Gemini AI Translation + SRT Overlay
    function parseSRTTime(str) {
        const m = String(str || "").trim().match(/(\d+):(\d+):(\d+)[,.](\d+)/);
        if (!m) return 0;
        return Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) + Number(m[4]) / 1000;
    }

    function parseSRT(raw) {
        const blocks = String(raw || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim().split(/\n\n+/);
        const cues = [];
        for (const block of blocks) {
            const lines = block.split("\n");
            const timingIdx = lines.findIndex(l => l.includes("-->"));
            if (timingIdx === -1) continue;
            const parts = lines[timingIdx].split("-->");
            if (parts.length < 2) continue;
            const start = parseSRTTime(parts[0]);
            const end = parseSRTTime(parts[1].split(" ")[0]);
            const text = lines.slice(timingIdx + 1).join("\n").replace(/<[^>]+>/g, "").trim();
            if (text && end > start) cues.push({ start, end, text });
        }
        return cues;
    }

    function updateSubtitleOverlay(sec) {
        const el = document.getElementById("subtitle-overlay");
        if (!state.player.subActive || !state.player.subCues.length) {
            el.classList.add("hidden");
            return;
        }
        const cue = state.player.subCues.find(c => sec >= c.start && sec <= c.end);
        if (cue) {
            el.textContent = cue.text;
            el.classList.remove("hidden");
        } else {
            el.classList.add("hidden");
        }
    }

    async function searchOpenSubtitles(query, lang, item) {
        const apiKey = state.subSettings.osKey;
        if (!apiKey) throw new Error("Add your OpenSubtitles API Key in Account → Subtitles.");

        async function runQuery(useSeason, useEpisode, useType) {
            const params = new URLSearchParams();
            if (useEpisode && item.episodeNumber) params.set("episode_number", String(item.episodeNumber));
            params.set("languages", lang);
            params.set("query", query.toLowerCase().trim());
            if (useSeason && item.seasonNumber) params.set("season_number", String(item.seasonNumber));
            if (useType) params.set("type", item.kind === "episode" ? "episode" : "movie");
            const res = await fetch(`https://api.opensubtitles.com/api/v1/subtitles?${params.toString()}`, {
                headers: { "Api-Key": apiKey, "User-Agent": "StreamFlixTV v1.0", "Accept": "application/json" }
            });
            if (res.status === 401 || res.status === 403) throw new Error("Invalid OpenSubtitles API Key.");
            if (!res.ok) throw new Error(`OpenSubtitles HTTP ${res.status}`);
            const json = await res.json();
            return (json.data || []).map(e => {
                const f = e.attributes && e.attributes.files && e.attributes.files[0];
                if (!f) return null;
                return {
                    fileId: f.file_id,
                    release: e.attributes.release || f.file_name || "Subtitle",
                    downloads: e.attributes.download_count || 0,
                    trusted: Boolean(e.attributes.from_trusted)
                };
            }).filter(Boolean).sort((a, b) => (b.trusted - a.trusted) || (b.downloads - a.downloads));
        }

        let res = await runQuery(true, true, true);
        if (!res.length && item.kind === "episode") res = await runQuery(false, true, true);
        if (!res.length) res = await runQuery(false, false, false);
        return res;
    }

    async function downloadOpenSubtitleText(fileId) {
        if (state.subCache[`raw_${fileId}`]) return state.subCache[`raw_${fileId}`];
        const apiKey = state.subSettings.osKey;
        const res = await fetch("https://api.opensubtitles.com/api/v1/download", {
            method: "POST",
            headers: {
                "Api-Key": apiKey,
                "User-Agent": "StreamFlixTV v1.0",
                "Accept": "application/json",
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ file_id: fileId, sub_format: "srt" })
        });
        if (!res.ok) throw new Error(`Download HTTP ${res.status}`);
        const json = await res.json();
        if (!json.link) throw new Error("No subtitle link returned.");
        const srtRes = await fetch(json.link);
        const text = await srtRes.text();
        state.subCache[`raw_${fileId}`] = text;
        return text;
    }

    async function translateSRTWithGemini(cues, targetLangCode, statusEl) {
        const key = state.subSettings.geminiKey;
        if (!key) throw new Error("Add your Gemini API Key in Account → Subtitles.");
        const langName = targetLangCode === "ar" ? "natural fluent Arabic" : "natural fluent Spanish";
        const batchSize = 45;
        const out = cues.slice();
        const totalBatches = Math.ceil(cues.length / batchSize);

        for (let b = 0; b < totalBatches; b++) {
            statusEl.textContent = `✨ Translating with AI (${Math.round(((b + 1) / totalBatches) * 100)}%)...`;
            const slice = cues.slice(b * batchSize, (b + 1) * batchSize);
            const lines = slice.map(c => c.text);
            const prompt = `Translate this JSON array of ${lines.length} subtitle lines into ${langName}. Return ONLY a valid JSON array of ${lines.length} strings in the exact same order.\n${JSON.stringify(lines)}`;
            const res = await fetch("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", {
                method: "POST",
                headers: { "Content-Type": "application/json", "x-goog-api-key": key },
                body: JSON.stringify({
                    contents: [{ parts: [{ text: prompt }] }],
                    generationConfig: { temperature: 0.2, responseMimeType: "application/json", thinkingConfig: { thinkingLevel: "minimal" } }
                })
            });
            if (!res.ok) throw new Error(`Gemini HTTP ${res.status}`);
            const data = await res.json();
            const raw = (data.candidates && data.candidates[0] && data.candidates[0].content && data.candidates[0].content.parts && data.candidates[0].content.parts[0] && data.candidates[0].content.parts[0].text) || "[]";
            const translated = JSON.parse(raw.replace(/```json|```/g, "").trim());
            for (let i = 0; i < slice.length; i++) {
                if (translated[i]) out[b * batchSize + i] = { ...slice[i], text: translated[i] };
            }
        }
        return out;
    }

    function openSubtitleModal() {
        const item = state.player.item;
        if (!item || item.kind === "live") return;
        const modal = document.getElementById("subtitle-modal");
        modal.classList.remove("hidden");

        const statusEl = document.getElementById("sub-modal-status");
        const listEl = document.getElementById("sub-results-list");
        const qInp = document.getElementById("inp-sub-query");
        const aiBtn = document.getElementById("btn-sub-ai-translate");
        qInp.value = cleanMediaTitle(item.title, item.kind).query;

        const refreshLangButtons = () => {
            ["en", "ar", "es"].forEach(code => {
                document.getElementById(`btn-sub-lang-${code}`).classList.toggle("active", state.subSettings.lang === code);
            });
            const showAI = state.subSettings.lang !== "en" && Boolean(state.subSettings.geminiKey) && Boolean(state.subSettings.osKey);
            aiBtn.classList.toggle("hidden", !showAI);
            if (showAI) {
                aiBtn.textContent = `✨ Translate English Subtitle with AI → ${SUB_LANGS[state.subSettings.lang].label}`;
            }
        };

        const runSubSearch = async () => {
            refreshLangButtons();
            if (!state.subSettings.osKey) {
                statusEl.textContent = "Add your OpenSubtitles API Key in Account → Subtitles first.";
                listEl.innerHTML = "";
                return;
            }
            statusEl.textContent = `Searching ${SUB_LANGS[state.subSettings.lang].label} subtitles...`;
            listEl.innerHTML = "";
            try {
                const results = await searchOpenSubtitles(qInp.value, state.subSettings.lang, item);
                statusEl.textContent = results.length ? `Found ${results.length} subtitles` : "No subtitles found. Try editing the title or use AI Translation.";
                results.slice(0, 25).forEach(sub => {
                    const row = document.createElement("button");
                    row.className = "channel-row tv-focusable";
                    row.innerHTML = `<span>${sub.trusted ? "✓ " : ""}${sub.release}</span><span class="ep-badge">⬇ ${sub.downloads}</span>`;
                    row.onclick = async () => {
                        statusEl.textContent = "Downloading subtitle...";
                        try {
                            const raw = await downloadOpenSubtitleText(sub.fileId);
                            state.player.subCues = parseSRT(raw);
                            state.player.subActive = true;
                            updateSubtitleOverlay(state.player.current);
                            modal.classList.add("hidden");
                            showToast(`${SUB_LANGS[state.subSettings.lang].flag} Subtitles Loaded`);
                            focusFirstInScope();
                        } catch (e) { statusEl.textContent = e.message; }
                    };
                    listEl.appendChild(row);
                });
            } catch (e) {
                statusEl.textContent = e.message;
            }
        };

        ["en", "ar", "es"].forEach(code => {
            document.getElementById(`btn-sub-lang-${code}`).onclick = () => {
                state.subSettings.lang = code;
                localStorage.setItem(KEYS.subLang, code);
                runSubSearch();
            };
        });

        document.getElementById("btn-sub-search").onclick = runSubSearch;
        document.getElementById("btn-sub-off").onclick = () => {
            state.player.subActive = false;
            state.player.subCues = [];
            updateSubtitleOverlay(0);
            modal.classList.add("hidden");
            showToast("Subtitles Off");
            focusFirstInScope();
        };
        document.getElementById("btn-close-sub").onclick = () => {
            modal.classList.add("hidden");
            focusFirstInScope();
        };

        aiBtn.onclick = async () => {
            try {
                statusEl.textContent = "Finding best English subtitle...";
                const enRes = await searchOpenSubtitles(qInp.value, "en", item);
                if (!enRes.length) { statusEl.textContent = "No English subtitle found to translate."; return; }
                const best = enRes[0];
                const cacheKey = `ai_${best.fileId}_${state.subSettings.lang}`;
                if (state.subCache[cacheKey]) {
                    state.player.subCues = state.subCache[cacheKey];
                } else {
                    const raw = await downloadOpenSubtitleText(best.fileId);
                    const enCues = parseSRT(raw);
                    const translated = await translateSRTWithGemini(enCues, state.subSettings.lang, statusEl);
                    state.subCache[cacheKey] = translated;
                    state.player.subCues = translated;
                }
                state.player.subActive = true;
                updateSubtitleOverlay(state.player.current);
                modal.classList.add("hidden");
                showToast(`✨ ${SUB_LANGS[state.subSettings.lang].flag} AI Subtitles Loaded`);
                focusFirstInScope();
            } catch (e) {
                statusEl.textContent = e.message;
            }
        };

        runSubSearch();
        focusFirstInScope();
    }

    function showToast(msg) {
        const toast = document.getElementById("player-toast");
        toast.textContent = msg;
        toast.classList.remove("hidden");
        clearTimeout(state.player.toastTimer);
        state.player.toastTimer = setTimeout(() => toast.classList.add("hidden"), 1100);
    }

    // MARK: - Playback (Samsung AVPlay + Browser HTML5 Fallback)
    function playMovie(m) {
        const ext = m.container_extension || "mp4";
        startPlayback({
            id: `movie-${m.stream_id}`,
            title: m.name,
            subtitle: m.rating ? `★ ${m.rating}` : "",
            artwork: m.stream_icon,
            kind: "movie",
            url: `${state.creds.host}/movie/${encodeURIComponent(state.creds.username)}/${encodeURIComponent(state.creds.password)}/${m.stream_id}.${ext}`
        });
    }

    function playChannel(ch, list) {
        state.liveList = list || state.live;
        state.liveIndex = state.liveList.findIndex(x => x.stream_id === ch.stream_id);
        showLiveBanner(ch, state.liveIndex + 1);
        startPlayback({
            id: `live-${ch.stream_id}`,
            title: ch.name,
            subtitle: "LIVE TV",
            artwork: ch.stream_icon,
            kind: "live",
            url: `${state.creds.host}/live/${encodeURIComponent(state.creds.username)}/${encodeURIComponent(state.creds.password)}/${ch.stream_id}.ts`,
            fallbackUrl: `${state.creds.host}/live/${encodeURIComponent(state.creds.username)}/${encodeURIComponent(state.creds.password)}/${ch.stream_id}.m3u8`
        });
    }
    function showLiveBanner(ch, num) {
        const b = document.getElementById("live-banner");
        document.getElementById("live-banner-num").textContent = String(num).padStart(3, "0");
        const img = document.getElementById("live-banner-img");
        img.style.opacity = ch.stream_icon ? "1" : "0";
        img.src = ch.stream_icon || "";
        document.getElementById("live-banner-name").textContent = ch.name;
        b.classList.remove("hidden");
        clearTimeout(state.player.bannerTimer);
        state.player.bannerTimer = setTimeout(() => b.classList.add("hidden"), 3500);
    }
    function openLiveDrawer() {
        const drawer = document.getElementById("live-drawer");
        const listEl = document.getElementById("live-drawer-list");
        listEl.innerHTML = "";
        drawer.classList.remove("hidden");
        const list = state.liveList || state.live;
        list.forEach((ch, idx) => {
            const btn = document.createElement("button");
            const isCur = idx === state.liveIndex;
            btn.className = "live-dish-row tv-focusable" + (isCur ? " active-cat" : "");
            btn.innerHTML = `<span class="live-num">${String(idx + 1).padStart(3, "0")}</span><span class="live-name">${ch.name}</span>`;
            btn.onclick = () => { closeLiveDrawer(); playChannel(ch, list); };
            listEl.appendChild(btn);
        });
        document.getElementById("btn-close-drawer").onclick = closeLiveDrawer;
        setTimeout(() => { const a = listEl.querySelector(".active-cat") || listEl.querySelector(".tv-focusable"); if (a) { a.focus(); try { a.scrollIntoView({ block: "center" }); } catch (e) {} } }, 50);
    }
    function closeLiveDrawer() {
        document.getElementById("live-drawer").classList.add("hidden");
    }

    function startPlayback(item, useFallback) {
        const screen = document.getElementById("player-screen");
        screen.classList.remove("hidden");
        state.player.item = item;
        state.player.isPaused = false;
        state.player.subCues = [];
        state.player.subActive = false;
        updateSubtitleOverlay(0);

        const playUrl = (useFallback && item.fallbackUrl) ? item.fallbackUrl : item.url;
        document.getElementById("player-paused-badge").classList.add("hidden");
        document.getElementById("hud-title").textContent = item.title;
        document.getElementById("hud-subtitle").textContent = item.subtitle || "";
        document.getElementById("btn-ch-prev").classList.toggle("hidden", item.kind !== "live");
        document.getElementById("btn-ch-next").classList.toggle("hidden", item.kind !== "live");
        document.getElementById("btn-subtitles").classList.toggle("hidden", item.kind === "live");
        document.getElementById("hud-progress-wrap").classList.toggle("hidden", item.kind === "live");

        const rec = state.progress[item.id];
        const isCompleted = rec && rec.duration > 0 && (rec.position / rec.duration) >= 0.93;
        const saved = (item.kind !== "live" && rec && !isCompleted) ? Math.max(0, rec.position - 2) : 0;

        if (window.webapis && webapis.avplay) {
            state.player.usingAVPlay = true;
            document.getElementById("html5-player").classList.add("hidden");
            try {
                webapis.avplay.close();
                webapis.avplay.open(playUrl);
                webapis.avplay.setDisplayRect(0, 0, 1920, 1080);
                webapis.avplay.setListener({
                    oncurrentplaytime: ms => {
                        state.player.current = ms / 1000;
                        state.player.total = webapis.avplay.getDuration() / 1000;
                        updatePlayerHUD();
                        updateSubtitleOverlay(state.player.current);
                    },
                    onerror: () => {
                        if (!useFallback && item.fallbackUrl) startPlayback(item, true);
                    },
                    onstreamcompleted: () => onStreamCompleted()
                });
                webapis.avplay.prepareAsync(() => {
                    if (saved > 2) webapis.avplay.seekTo(saved * 1000);
                    webapis.avplay.play();
                }, () => {
                    if (!useFallback && item.fallbackUrl) startPlayback(item, true);
                });
            } catch (e) {
                if (!useFallback && item.fallbackUrl) startPlayback(item, true);
            }
        } else {
            state.player.usingAVPlay = false;
            const v = document.getElementById("html5-player");
            v.classList.remove("hidden");
            v.src = playUrl;
            v.onloadedmetadata = () => { if (saved > 2) v.currentTime = saved; v.play(); };
            v.ontimeupdate = () => {
                state.player.current = v.currentTime;
                state.player.total = v.duration || 0;
                updatePlayerHUD();
                updateSubtitleOverlay(state.player.current);
            };
            v.onended = () => onStreamCompleted();
        }
        revealHUD();
    }

    function updatePlayerHUD() {
        const { current, total, item } = state.player;
        document.getElementById("hud-cur-time").textContent = formatTime(current);
        document.getElementById("hud-tot-time").textContent = formatTime(total);
        document.getElementById("hud-progress-fill").style.width = total > 0 ? `${Math.min(100, (current / total) * 100)}%` : "0%";
        if (item && item.kind !== "live" && total > 0 && current > 2) {
            const prev = state.progress[item.id];
            state.progress[item.id] = { item, position: current, duration: total, updatedAt: Date.now() };
            localStorage.setItem(KEYS.progress, JSON.stringify(state.progress));
            if (!prev || Math.abs(current - prev.position) >= 15) {
                scheduleCloudPush();
            }
        }
    }

    function togglePlayPause() {
        state.player.isPaused = !state.player.isPaused;
        document.getElementById("player-paused-badge").classList.toggle("hidden", !state.player.isPaused);
        if (state.player.usingAVPlay) {
            state.player.isPaused ? webapis.avplay.pause() : webapis.avplay.play();
        } else {
            const v = document.getElementById("html5-player");
            state.player.isPaused ? v.pause() : v.play();
        }
        revealHUD();
    }

    function skipSeconds(delta) {
        if (!state.player.item || state.player.item.kind === "live") return;
        const target = Math.max(0, (state.player.current || 0) + delta);
        state.player.current = target;
        updatePlayerHUD();
        updateSubtitleOverlay(target);
        if (state.player.usingAVPlay) webapis.avplay.seekTo(target * 1000);
        else document.getElementById("html5-player").currentTime = target;
        showToast(delta > 0 ? `⏩ +${delta}s` : `⏪ ${delta}s`);
        revealHUD();
    }

    function stopPlayer() {
        updatePlayerHUD();
        scheduleCloudPush();
        state.player.subActive = false;
        state.player.subCues = [];
        updateSubtitleOverlay(0);
        if (state.player.usingAVPlay) {
            try { webapis.avplay.stop(); webapis.avplay.close(); } catch (e) {}
        } else {
            const v = document.getElementById("html5-player");
            v.pause(); v.src = "";
        }
        document.getElementById("player-screen").classList.add("hidden");
        renderTab();
    }

    function onStreamCompleted() {
        const next = state.player.item && state.player.item.nextItem;
        if (!next) return stopPlayer();
        state.player.consecutiveAuto += 1;
        if (state.player.consecutiveAuto >= 2) {
            const sm = document.getElementById("sleep-modal");
            sm.classList.remove("hidden");
            let sec = 60;
            document.getElementById("sleep-countdown").textContent = sec;
            clearInterval(state.player.sleepInterval);
            state.player.sleepInterval = setInterval(() => {
                sec -= 1;
                document.getElementById("sleep-countdown").textContent = sec;
                if (sec <= 0) { clearInterval(state.player.sleepInterval); sm.classList.add("hidden"); stopPlayer(); }
            }, 1000);
            document.getElementById("btn-still-watching").onclick = () => {
                clearInterval(state.player.sleepInterval);
                sm.classList.add("hidden");
                state.player.consecutiveAuto = 0;
                startPlayback(next);
            };
            document.getElementById("btn-sleep-exit").onclick = () => {
                clearInterval(state.player.sleepInterval);
                sm.classList.add("hidden");
                stopPlayer();
            };
        } else {
            startPlayback(next);
        }
    }

    function revealHUD() {
        const hud = document.getElementById("player-hud");
        hud.classList.remove("hidden");
        clearTimeout(state.player.hudTimer);
        if (!state.player.isPaused) {
            state.player.hudTimer = setTimeout(() => hud.classList.add("hidden"), 3500);
        }
    }

    // Wire UI Events
    document.getElementById("btn-signin").onclick = () => signIn({
        profileName: document.getElementById("inp-profile").value || "Living Room TV",
        host: document.getElementById("inp-host").value,
        username: document.getElementById("inp-user").value,
        password: document.getElementById("inp-pass").value
    });

    document.querySelectorAll(".nav-tab").forEach(btn => {
        btn.onclick = () => {
            document.querySelectorAll(".nav-tab").forEach(x => x.classList.remove("active"));
            btn.classList.add("active");
            state.tab = btn.dataset.tab;
            renderTab();
        };
    });

    function exitApp() {
        try {
            if (window.tizen && tizen.application) {
                tizen.application.getCurrentApplication().exit();
                return;
            }
        } catch (err) {}
        window.close();
    }

    document.getElementById("btn-exit-app").onclick = exitApp;
    document.getElementById("btn-login-exit").onclick = exitApp;

    let searchDebounce = null;
    document.getElementById("global-search").oninput = e => {
        const val = e.target.value;
        clearTimeout(searchDebounce);
        searchDebounce = setTimeout(() => { state.search = val; renderTab(); }, 280);
    };
    document.getElementById("btn-player-back").onclick = stopPlayer;
    document.getElementById("btn-play-pause").onclick = togglePlayPause;
    document.getElementById("btn-subtitles").onclick = openSubtitleModal;
    document.getElementById("btn-skip-back").onclick = () => skipSeconds(-10);
    document.getElementById("btn-skip-fwd").onclick = () => skipSeconds(10);
    document.getElementById("btn-ch-prev").onclick = () => {
        if (!state.liveList || !state.liveList.length) return;
        state.liveIndex = (state.liveIndex - 1 + state.liveList.length) % state.liveList.length;
        playChannel(state.liveList[state.liveIndex], state.liveList);
    };
    document.getElementById("btn-ch-next").onclick = () => {
        if (!state.liveList || !state.liveList.length) return;
        state.liveIndex = (state.liveIndex + 1) % state.liveList.length;
        playChannel(state.liveList[state.liveIndex], state.liveList);
    };

    // Samsung Remote Key Handling (D-Pad Spatial Navigation + Player + Return)
    function getActiveScope() {
        const sleep = document.getElementById("sleep-modal");
        if (!sleep.classList.contains("hidden")) return sleep;
        const subModal = document.getElementById("subtitle-modal");
        if (!subModal.classList.contains("hidden")) return subModal;
        const drawer = document.getElementById("live-drawer");
        if (!drawer.classList.contains("hidden")) return drawer;
        const player = document.getElementById("player-screen");
        if (!player.classList.contains("hidden")) return player;
        const catModal = document.getElementById("category-modal");
        if (!catModal.classList.contains("hidden")) return catModal;
        const seriesModal = document.getElementById("series-modal");
        if (!seriesModal.classList.contains("hidden")) return seriesModal;
        const main = document.getElementById("main-screen");
        if (main.classList.contains("active")) return main;
        return document.getElementById("login-screen");
    }

    function getFocusables(scope) {
        return Array.from(scope.querySelectorAll(".tv-focusable")).filter(el => {
            if (el.classList.contains("hidden") || el.disabled) return false;
            const r = el.getBoundingClientRect();
            return r.width > 0 && r.height > 0;
        });
    }

    function focusFirstInScope() {
        setTimeout(() => {
            const list = getFocusables(getActiveScope());
            if (list.length) list[0].focus();
        }, 60);
    }

    function moveFocus(dir) {
        const scope = getActiveScope();
        const items = getFocusables(scope);
        if (!items.length) return;
        const cur = document.activeElement;
        if (!cur || !items.includes(cur)) {
            items[0].focus();
            return;
        }

        // Clean pane-to-pane navigation between Sidebar and Main Pane
        if (cur.closest(".tv-sidebar") && dir === "right") {
            const pane = scope.querySelector(".tv-main-pane");
            if (pane) {
                const paneItems = getFocusables(pane);
                const visible = paneItems.find(el => {
                    const r = el.getBoundingClientRect();
                    return r.top >= 80 && r.bottom <= 1080;
                }) || paneItems[0];
                if (visible) {
                    visible.focus();
                    try { visible.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" }); } catch (e) {}
                    return;
                }
            }
        }

        const cr = cur.getBoundingClientRect();
        const cx = cr.left + cr.width / 2;
        const cy = cr.top + cr.height / 2;

        let best = null;
        let bestScore = Infinity;

        items.forEach(el => {
            if (el === cur) return;
            const r = el.getBoundingClientRect();
            const ex = r.left + r.width / 2;
            const ey = r.top + r.height / 2;
            const dx = ex - cx;
            const dy = ey - cy;

            let valid = false;
            let primary = 0;
            let secondary = 0;

            if (dir === "up" && dy < -10) { valid = true; primary = -dy; secondary = Math.abs(dx); }
            else if (dir === "down" && dy > 10) { valid = true; primary = dy; secondary = Math.abs(dx); }
            else if (dir === "left" && dx < -10) { valid = true; primary = -dx; secondary = Math.abs(dy); }
            else if (dir === "right" && dx > 10) { valid = true; primary = dx; secondary = Math.abs(dy); }

            if (!valid) return;
            const score = primary + secondary * 2.5;
            if (score < bestScore) {
                bestScore = score;
                best = el;
            }
        });

        if (best) {
            if (cur.closest(".tv-main-pane") && dir === "left" && best.closest(".tv-sidebar")) {
                const activeCat = scope.querySelector(".tv-sidebar .cat-item.active");
                if (activeCat) best = activeCat;
            }
            best.focus();
            try { best.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" }); } catch (e) {}
        }
    }

    document.addEventListener("keydown", e => {
        const k = e.keyCode;
        const playerOpen = !document.getElementById("player-screen").classList.contains("hidden");
        const sleepOpen = !document.getElementById("sleep-modal").classList.contains("hidden");
        const subOpen = !document.getElementById("subtitle-modal").classList.contains("hidden");
        const active = document.activeElement;
        const isInput = active && (active.tagName === "INPUT" || active.tagName === "SELECT");

        // Samsung TV Return Key (10009) or Escape
        if (k === 10009 || e.key === "Escape") {
            e.preventDefault();
            if (isInput && !active.readOnly) {
                active.readOnly = true;
                active.blur();
                setTimeout(() => active.focus(), 20);
                return;
            }
            if (sleepOpen) {
                document.getElementById("btn-sleep-exit").click();
            } else if (subOpen) {
                document.getElementById("subtitle-modal").classList.add("hidden");
                focusFirstInScope();
            } else if (!document.getElementById("live-drawer").classList.contains("hidden")) {
                closeLiveDrawer();
            } else if (playerOpen) {
                closeLiveDrawer();
                document.getElementById("live-banner").classList.add("hidden");
                stopPlayer();
                focusFirstInScope();
            } else if (!document.getElementById("category-modal").classList.contains("hidden")) {
                document.getElementById("category-modal").classList.add("hidden");
                focusFirstInScope();
            } else if (!document.getElementById("series-modal").classList.contains("hidden")) {
                document.getElementById("series-modal").classList.add("hidden");
                focusFirstInScope();
            } else if (document.getElementById("main-screen").classList.contains("active")) {
                if (state.search) {
                    state.search = "";
                    document.getElementById("global-search").value = "";
                    renderTab();
                    focusFirstInScope();
                } else if (state.tab !== "home") {
                    document.querySelector('.nav-tab[data-tab="home"]').click();
                    focusFirstInScope();
                } else {
                    exitApp();
                }
            }
            return;
        }

        // Player-specific keys (Dish Mode for Live TV + Instant Seek for VOD)
        if (playerOpen && !sleepOpen && !subOpen) {
            const drawerOpen = !document.getElementById("live-drawer").classList.contains("hidden");
            const hudHidden = document.getElementById("player-hud").classList.contains("hidden");
            const isLive = state.player.item && state.player.item.kind === "live";
            if (k === 10252 || k === 415 || k === 19) { e.preventDefault(); togglePlayPause(); return; }
            if (isLive && !drawerOpen) {
                if (k === 427 || k === 38) { e.preventDefault(); document.getElementById("btn-ch-next").click(); return; }
                if (k === 428 || k === 40) { e.preventDefault(); document.getElementById("btn-ch-prev").click(); return; }
                if (k === 13 || k === 37) { e.preventDefault(); openLiveDrawer(); return; }
            }
            if (!isLive) {
                if (k === 412 || k === 37) { e.preventDefault(); skipSeconds(-10); return; }
                if (k === 417 || k === 39) { e.preventDefault(); skipSeconds(10); return; }
                if (hudHidden && k === 13) { e.preventDefault(); togglePlayPause(); return; }
                if (hudHidden && (k === 38 || k === 40)) { e.preventDefault(); revealHUD(); focusFirstInScope(); return; }
            }
        }

        // Input IME Done / Cancel keys on Samsung TV
        if (isInput && (k === 65376 || k === 65385)) {
            e.preventDefault();
            active.readOnly = true;
            moveFocus("down");
            return;
        }

        // D-Pad Spatial Navigation
        if (k === 38) {
            e.preventDefault();
            if (isInput && !active.readOnly) active.readOnly = true;
            moveFocus("up");
        } else if (k === 40) {
            e.preventDefault();
            if (isInput && !active.readOnly) active.readOnly = true;
            moveFocus("down");
        } else if (k === 37 && (!isInput || active.readOnly)) {
            e.preventDefault();
            moveFocus("left");
        } else if (k === 39 && (!isInput || active.readOnly)) {
            e.preventDefault();
            moveFocus("right");
        } else if (k === 13) {
            if (active && active.classList.contains("tv-focusable")) {
                if (active.tagName === "INPUT") {
                    if (active.readOnly) {
                        active.readOnly = false;
                        active.select();
                    } else {
                        e.preventDefault();
                        active.readOnly = true;
                        moveFocus("down");
                    }
                } else if (active.tagName === "BUTTON") {
                    e.preventDefault();
                    active.click();
                }
            } else {
                focusFirstInScope();
            }
        }
    });

    // Keep inputs readOnly while navigating so Samsung TV keyboard doesn't trap D-Pad arrows
    document.querySelectorAll("input.tv-focusable").forEach(bindTVInput);

    renderSavedProfiles();
    focusFirstInScope();

    // Pre-fill & auto-login if a saved profile exists
    const savedList = JSON.parse(localStorage.getItem(KEYS.profiles) || "[]");
    if (savedList.length > 0) {
        const p = savedList[0];
        document.getElementById("inp-profile").value = p.profileName || "Living Room TV";
        document.getElementById("inp-host").value = p.host || "";
        document.getElementById("inp-user").value = p.username || "";
        document.getElementById("inp-pass").value = p.password || "";
        signIn(p);
    }
})();
