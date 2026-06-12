(() => {
    const DEFAULT_STATE = { root: 'outputs', path: '', page: 1, pageSize: 15, search: '', sort: 'name', order: 'asc' };

    const fmtBytes = (value) => {
        const n = Number(value || 0);
        if (!Number.isFinite(n) || n <= 0) return '0 B';
        const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
        let size = n;
        let unit = 0;
        while (size >= 1024 && unit < units.length - 1) {
            size /= 1024;
            unit += 1;
        }
        return `${size.toFixed(unit ? 1 : 0)} ${units[unit]}`;
    };

    async function api(path, options) {
        const res = await fetch(path, options);
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(JSON.stringify(data));
        return data;
    }

    function create(options) {
        const state = Object.assign({}, DEFAULT_STATE, options.state || {});
        const filesEl = options.filesEl;
        const rootsEl = options.rootsEl || null;
        const setStatusWindow = options.setStatusWindow || ((_title, value) => {
            if (options.show) options.show(value);
        });
        const getSearch = options.getSearch || (() => '');
        const getSort = options.getSort || (() => 'name');
        const getOrder = options.getOrder || (() => 'asc');
        const filePageEl = options.filePageEl || null;
        const buttonClass = options.buttonClass || 'secondary';
        const linkClass = options.linkClass || buttonClass;
        const metaClass = options.metaClass || 'pill';
        const rootButtonLabel = options.rootButtonLabel || ((root) => `${root.name} · ${root.path}`);
        const onFile = options.onFile || ((entry) => setStatusWindow(`File · ${entry.name}`, entry));
        const onDirectoryErrorTitle = options.onDirectoryErrorTitle || 'Files Error';

        function buildFileUrl(root, path) {
            return path ? `/api/v1/files/${root}/${encodeURIComponent(path).replace(/%2F/g, '/')}` : `/api/v1/files/${root}`;
        }

        function renderIpfs(entry, row) {
            const ipfs = entry.ipfs || {};
            const status = ipfs.status || 'none';
            const target = row.querySelector('.file-name') || row;
            const pill = document.createElement('span');
            pill.className = `${metaClass} ${status === 'pinned' ? 'ok' : status === 'failed' ? 'error' : status === 'manual_required' ? 'warn' : ''}`;
            pill.textContent = `IPFS ${status}`;
            target.appendChild(pill);

            if (status === 'pinned' && ipfs.gatewayUrl) {
                const local = document.createElement('a');
                local.className = linkClass;
                local.href = ipfs.gatewayUrl;
                local.target = '_blank';
                local.rel = 'noreferrer';
                local.textContent = 'IPFS';
                target.appendChild(local);
                if (ipfs.publicGatewayUrl) {
                    const pub = document.createElement('a');
                    pub.className = linkClass;
                    pub.href = ipfs.publicGatewayUrl;
                    pub.target = '_blank';
                    pub.rel = 'noreferrer';
                    pub.textContent = 'ipfs.io';
                    target.appendChild(pub);
                }
            }

            if (status === 'failed' || status === 'manual_required') {
                const retry = document.createElement('button');
                retry.className = buttonClass;
                retry.textContent = status === 'manual_required' ? '手动备份到 IPFS' : '重试 IPFS';
                retry.addEventListener('click', async () => {
                    const data = await api('/api/v1/ipfs/backup', {
                        method: 'POST',
                        headers: { 'content-type': 'application/json' },
                        body: JSON.stringify({ root: entry.root, path: entry.path, force: true })
                    });
                    setStatusWindow('IPFS Backup', data);
                    setTimeout(() => loadFiles(state.root, state.path, state.page).catch((error) => setStatusWindow(onDirectoryErrorTitle, String(error))), 1200);
                });
                target.appendChild(retry);
            }
        }

        async function loadRoots() {
            const data = await api('/api/v1/files');
            if (rootsEl) {
                rootsEl.innerHTML = '';
                (data.roots || []).forEach((root) => {
                    const button = document.createElement('button');
                    button.className = buttonClass;
                    button.textContent = rootButtonLabel(root);
                    button.addEventListener('click', () => loadFiles(root.name, '', 1).catch((error) => setStatusWindow(onDirectoryErrorTitle, String(error))));
                    rootsEl.appendChild(button);
                });
            }
            if ((data.roots || []).length) state.root = data.roots[0].name;
            return data;
        }

        async function loadFiles(root = state.root, path = state.path, page = state.page) {
            state.root = root;
            state.path = path || '';
            state.page = page;
            state.search = getSearch();
            state.sort = getSort();
            state.order = getOrder();
            const params = new URLSearchParams({ page: String(state.page), pageSize: String(state.pageSize), search: state.search, sort: state.sort, order: state.order });
            const data = await api(`${buildFileUrl(state.root, state.path)}?${params}`);
            setStatusWindow(`Files · ${root}`, data);
            filesEl.innerHTML = '';
            let shouldPoll = false;
            (data.entries || []).forEach((entry) => {
                const row = document.createElement('div');
                row.className = 'file-item';
                const left = document.createElement('div');
                left.className = 'file-name';
                const action = document.createElement('button');
                action.className = buttonClass;
                action.textContent = `${entry.type === 'directory' ? '📁' : '📄'} ${entry.name}`;
                action.addEventListener('click', () => {
                    if (entry.type === 'directory') {
                        loadFiles(entry.root, entry.path, 1).catch((error) => setStatusWindow(onDirectoryErrorTitle, String(error)));
                    } else {
                        onFile(entry);
                    }
                });
                left.appendChild(action);
                row.appendChild(left);
                const meta = document.createElement('span');
                meta.className = metaClass;
                meta.textContent = `${entry.type} · ${fmtBytes(entry.size)}`;
                row.appendChild(meta);
                if (entry.type === 'file') renderIpfs(entry, row);
                const st = entry.ipfs?.status;
                if (st === 'queued' || st === 'uploading') shouldPoll = true;
                filesEl.appendChild(row);
            });
            const p = data.pagination || {};
            if (filePageEl) filePageEl.textContent = `Page ${p.page || 1}/${p.pages || 1} · ${p.total || 0} items`;
            if (shouldPoll) setTimeout(() => loadFiles(state.root, state.path, state.page).catch(() => { }), 4000);
            return data;
        }

        return { state, fmtBytes, api, renderIpfs, loadRoots, loadFiles };
    }

    window.XForceFileBrowser = { create, fmtBytes, api };
})();
