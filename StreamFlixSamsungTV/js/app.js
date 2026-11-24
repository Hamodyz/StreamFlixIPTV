// StreamFlix IPTV — Samsung Tizen Smart TV App Logic
(function () {
    const KEYS = {
        profiles: "sf_tv_profiles_v1",
        progress: "sf_tv_progress_v1",
        favMovies: "sf_tv_fav_movies_v1",
        favSeries: "sf_tv_fav_series_v1",
        favChannels: "sf_tv_fav_channels_v1"
    };

    const state = {
        creds: null,
        authInfo: null,
        tab: "home",
        search: "",
        liveCats: [], live: [],
        vodCats: [], movies: [],
        serCats: [], series: [],
        selectedCat: { movies: null, series: null, live: null },
        progress: JSON.parse(localStorage.getItem(KEYS.progress) || "{}"),
        favMovies: new Set(JSON.parse(localStorage.getItem(KEYS.favMovies) || "[]")),
        favSeries: new Set(JSON.parse(localStorage.getItem(KEYS.favSeries) || "[]")),
        favChannels: new Set(JSON.parse(localStorage.getItem(KEYS.favChannels) || "[]")),
        player: { item: null, current: 0, total: 0, isPaused: false, usingAVPlay: false, timer: null, hudTimer: null, consecutiveAuto: 0, sleepInterval: null }
    };

    // Register Samsung TV Remote Keys
    if (window.tizen && tizen.tvinputdevice) {
        ["MediaPlayPause", "MediaPlay", "MediaPause", "MediaFastForward", "MediaRewind", "ChannelUp", "ChannelDown"].forEach(k => {
            try { tizen.tvinputdevice.registerKey(k); } catch (e) {}
        });
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

    function matches(title, query) {
        const q = normalizeArabic(query);
        return !q || normalizeArabic(title).includes(q);
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
        renderTab();
    }

    // MARK: - Rendering Tabs
    function posterCard(title, img, progressFrac, onClick) {
        const btn = document.createElement("button");
        btn.className = "poster-card tv-focusable";
        btn.onclick = onClick;
        btn.innerHTML = `<img src="${img || ""}" loading="lazy" onerror="this.style.opacity=0.2">` +
            (progressFrac ? `<div class="progress-bar-mini"><div style="width:${Math.round(progressFrac * 100)}%"></div></div>` : "") +
            `<div class="poster-title">${title}</div>`;
        return btn;
    }

    function renderTab() {
        const area = document.getElementById("content-area");
        area.innerHTML = "";

        if (state.search.trim()) {
            const q = state.search.trim();
            const fSeries = state.series.filter(x => matches(x.name, q)).slice(0, 35);
            const fMovies = state.movies.filter(x => matches(x.name, q)).slice(0, 35);
            const fLive = state.live.filter(x => matches(x.name, q)).slice(0, 25);
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
            const hero = state.movies.find(m => m.stream_icon) || state.movies[0];
            if (hero) {
                const hb = document.createElement("div");
                hb.className = "hero-banner";
                hb.innerHTML = `<img class="hero-backdrop" src="${hero.stream_icon || ""}" onerror="this.style.display='none'"><div class="hero-overlay"><span class="hero-badge">FEATURED</span><h2>${hero.name}</h2></div><img class="hero-poster" src="${hero.stream_icon || ""}" onerror="this.style.display='none'">`;
                const playBtn = document.createElement("button");
                playBtn.className = "btn-primary tv-focusable";
                playBtn.textContent = "▶ Play";
                playBtn.onclick = () => playMovie(hero);
                hb.querySelector(".hero-overlay").appendChild(playBtn);
                area.appendChild(hb);
            }

            // Continue Watching
            const cw = Object.values(state.progress).filter(r => r.position >= 5 && r.duration > 0 && (r.position / r.duration) < 0.93).sort((a, b) => b.updatedAt - a.updatedAt);
            if (cw.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Continue Watching</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                cw.forEach(r => row.appendChild(posterCard(r.item.title, r.item.artwork, r.position / r.duration, () => startPlayback(r.item))));
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

            // Trending Movies
            const trending = state.movies.filter(m => m.stream_icon).slice(0, 20);
            if (trending.length) {
                area.insertAdjacentHTML("beforeend", `<div class="section-title">Trending Movies 🔥</div>`);
                const row = document.createElement("div"); row.className = "carousel-row";
                trending.forEach(m => row.appendChild(posterCard(m.name, m.stream_icon, 0, () => playMovie(m))));
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
            area.innerHTML = `<div class="section-title">Account</div>
                <p style="font-size:22px; margin-bottom:12px;">Profile: <strong>${state.creds.profileName}</strong></p>
                <p style="font-size:22px; margin-bottom:12px;">Server: ${state.creds.host}</p>
                <p style="font-size:22px; margin-bottom:24px;">Connections: ${ui.active_cons || 0} / ${ui.max_connections || 1}</p>`;
            const outBtn = document.createElement("button");
            outBtn.className = "btn-primary tv-focusable";
            outBtn.textContent = "Sign Out";
            outBtn.onclick = () => {
                document.getElementById("main-screen").classList.remove("active");
                document.getElementById("login-screen").classList.add("active");
                renderSavedProfiles();
            };
            area.appendChild(outBtn);
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
            btn.innerHTML = `<span class="live-num">${String(num).padStart(3, "0")}</span><img src="${ch.stream_icon || ""}" style="width:44px;height:32px;object-fit:contain;flex-shrink:0;" onerror="this.style.opacity=0.2"><span class="live-name">${ch.name}</span>`;
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

    // MARK: - Series Modal
    async function openSeriesModal(series) {
        const modal = document.getElementById("series-modal");
        modal.classList.remove("hidden");
        document.getElementById("series-modal-title").textContent = series.name;
        document.getElementById("series-modal-plot").textContent = series.plot || "";

        const favBtn = document.getElementById("btn-fav-series");
        const updateFavBtn = () => favBtn.textContent = state.favSeries.has(series.series_id) ? "♥ In My List" : "♡ My List";
        updateFavBtn();
        favBtn.onclick = () => {
            if (state.favSeries.has(series.series_id)) state.favSeries.delete(series.series_id);
            else state.favSeries.add(series.series_id);
            localStorage.setItem(KEYS.favSeries, JSON.stringify([...state.favSeries]));
            updateFavBtn();
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
                    row.className = "channel-row tv-focusable";
                    row.innerHTML = `<span>▶ S${sKey}:E${ep.episode_num} — ${ep.title}</span>`;
                    row.onclick = () => {
                        modal.classList.add("hidden");
                        const ext = ep.container_extension || "mp4";
                        const nextEp = eps[i + 1] ? {
                            id: `ep-${eps[i + 1].id}`,
                            title: `${series.name} • S${sKey}:E${eps[i + 1].episode_num}`,
                            subtitle: eps[i + 1].title,
                            artwork: series.cover,
                            kind: "episode",
                            url: `${state.creds.host}/series/${state.creds.username}/${state.creds.password}/${eps[i + 1].id}.${eps[i + 1].container_extension || "mp4"}`
                        } : null;
                        startPlayback({
                            id: `ep-${ep.id}`,
                            title: `${series.name} • S${sKey}:E${ep.episode_num}`,
                            subtitle: ep.title,
                            artwork: series.cover,
                            kind: "episode",
                            url: `${state.creds.host}/series/${state.creds.username}/${state.creds.password}/${ep.id}.${ext}`,
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
            if (seasons.length) showSeason(seasons[0]);
            focusFirstInScope();
        } catch (e) {
            epBox.innerHTML = "<p>Could not load episodes.</p>";
        }
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
            url: `${state.creds.host}/movie/${state.creds.username}/${state.creds.password}/${m.stream_id}.${ext}`
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
            url: `${state.creds.host}/live/${state.creds.username}/${state.creds.password}/${ch.stream_id}.ts`,
            fallbackUrl: `${state.creds.host}/live/${state.creds.username}/${state.creds.password}/${ch.stream_id}.m3u8`
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
        const playUrl = (useFallback && item.fallbackUrl) ? item.fallbackUrl : item.url;
        document.getElementById("player-paused-badge").classList.add("hidden");
        document.getElementById("hud-title").textContent = item.title;
        document.getElementById("hud-subtitle").textContent = item.subtitle || "";
        document.getElementById("btn-ch-prev").classList.toggle("hidden", item.kind !== "live");
        document.getElementById("btn-ch-next").classList.toggle("hidden", item.kind !== "live");
        document.getElementById("hud-progress-wrap").classList.toggle("hidden", item.kind === "live");

        const saved = (item.kind !== "live" && state.progress[item.id]) ? Math.max(0, state.progress[item.id].position - 2) : 0;

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
            state.progress[item.id] = { item, position: current, duration: total, updatedAt: Date.now() };
            localStorage.setItem(KEYS.progress, JSON.stringify(state.progress));
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
        if (state.player.usingAVPlay) webapis.avplay.seekTo(target * 1000);
        else document.getElementById("html5-player").currentTime = target;
        const toast = document.getElementById("player-toast");
        toast.textContent = delta > 0 ? `⏩ +${delta}s` : `⏪ ${delta}s`;
        toast.classList.remove("hidden");
        clearTimeout(state.player.toastTimer);
        state.player.toastTimer = setTimeout(() => toast.classList.add("hidden"), 800);
        revealHUD();
    }

    function stopPlayer() {
        updatePlayerHUD();
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
        if (playerOpen && !sleepOpen) {
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
    document.querySelectorAll("input.tv-focusable").forEach(inp => {
        inp.readOnly = true;
        inp.addEventListener("blur", () => { inp.readOnly = true; });
    });

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
