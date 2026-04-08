'use strict';

import { readfile, popen, stat } from 'fs';

const BIN_DIRS = ['/opt/tailscale', '/tmp/tailscale'];

const VALID_SOURCES  = { 'official': true, 'small': true };
const VALID_STORAGES = { 'persistent': true, 'ram': true };
const VALID_ACTIONS  = { 'start': true, 'stop': true, 'restart': true };

function shell(cmd) {
	let h = popen(cmd + ' 2>&1', 'r');
	if (!h)
		return { code: -1, stdout: '' };

	let stdout = h.read('all') || '';
	let code = h.close();
	return { code, stdout };
}

function read_first_line(path) {
	let content = readfile(path);
	if (content == null)
		return null;
	content = trim(content);
	return length(content) ? content : null;
}

function find_bin_dir() {
	for (let d in BIN_DIRS) {
		if (stat(BIN_DIRS[d] + '/version'))
			return BIN_DIRS[d];
	}
	return null;
}

function get_configured_source() {
	let r = shell("uci -q get tailscale.settings.download_source 2>/dev/null");
	if (r.code != 0 || !r.stdout)
		return null;

	let source = trim(r.stdout);
	return VALID_SOURCES[source] ? source : null;
}

function get_installed_source(bin_dir) {
	if (!bin_dir)
		return null;

	let source = read_first_line(bin_dir + '/source');
	if (VALID_SOURCES[source])
		return source;

	if (stat(bin_dir + '/tailscale.combined'))
		return 'small';

	return get_configured_source();
}

function is_valid_version(v) {
	if (type(v) != 'string' || !length(v))
		return false;
	return !!match(v, /^[0-9]+(\.[0-9]+)+$/);
}

function clamp_int(v, lo, hi) {
	v = +v;
	if (type(v) != 'double' && type(v) != 'int')
		return lo;
	if (v != v) return lo;
	if (v < lo) return lo;
	if (v > hi) return hi;
	return int(v);
}

const methods = {
	get_install_info: {
		call: function() {
			let bin_dir = find_bin_dir();
			let arch_r = shell('uname -m');
			let arch = trim(arch_r.stdout);
			if (!length(arch))
				arch = null;

			if (!bin_dir)
				return { installed: false, version: null, source: null, bin_dir: null, arch: arch };

			let version = read_first_line(bin_dir + '/version');
			let source = get_installed_source(bin_dir);

			return {
				installed: true,
				version: version,
				source: source,
				bin_dir: bin_dir,
				arch: arch
			};
		}
	},

	get_status: {
		call: function() {
			let bin_dir = find_bin_dir();
			let installed = !!bin_dir;
			let result = {
				installed: installed,
				running: false,
				pid: null,
				installed_version: null,
				source_type: null,
				tun_mode: null,
				backend_state: null,
				tailscale_ips: [],
				hostname: null,
				peers: []
			};

			if (!installed)
				return result;

			result.installed_version = read_first_line(bin_dir + '/version');
			result.source_type = get_installed_source(bin_dir);

			let pid_r = shell('pidof tailscaled');
			if (pid_r.code != 0 || !trim(pid_r.stdout))
				return result;

			let pid_str = split(trim(pid_r.stdout), ' ')[0];
			result.running = true;
			result.pid = +pid_str;

			let cmdline = readfile('/proc/' + pid_str + '/cmdline');
			if (cmdline && index(cmdline, 'userspace-networking') >= 0)
				result.tun_mode = 'userspace';
			else
				result.tun_mode = 'kernel';

			let ts_r = shell('tailscale status --json 2>/dev/null');
			if (ts_r.code != 0 || !ts_r.stdout)
				return result;

			let ts = json(ts_r.stdout);
			if (!ts)
				return result;

			result.backend_state = ts.BackendState;

			if (ts.Self) {
				result.tailscale_ips = ts.Self.TailscaleIPs || [];
				result.hostname = ts.Self.HostName;
			}

			if (ts.Peer) {
				for (let key in ts.Peer) {
					let p = ts.Peer[key];
					push(result.peers, {
						hostname: p.HostName,
						dns_name: p.DNSName,
						ip: (p.TailscaleIPs && length(p.TailscaleIPs)) ? p.TailscaleIPs[0] : null,
						os: p.OS,
						online: p.Online,
						exit_node: p.ExitNode || false,
						rx_bytes: p.RxBytes,
						tx_bytes: p.TxBytes,
						last_seen: p.LastSeen
					});
				}
			}

			return result;
		}
	},

	service_control: {
		args: { action: '' },
		call: function(req) {
			let args = (req && req.args) ? req.args : {};
			if (!VALID_ACTIONS[args.action])
				return { code: -1, stdout: 'Invalid action: must be start, stop, or restart' };

			return shell('/etc/init.d/tailscale ' + args.action);
		}
	},

	do_install: {
		args: { source: '', storage: '', auto_update: '' },
		call: function(req) {
			let args = (req && req.args) ? req.args : {};
			let cmd = 'tailscale-manager install-quiet';

			if (args.source && length(args.source)) {
				if (!VALID_SOURCES[args.source])
					return { code: -1, stdout: 'Invalid source: must be official or small' };
				cmd += ' --source ' + args.source;
			}
			if (args.storage && length(args.storage)) {
				if (!VALID_STORAGES[args.storage])
					return { code: -1, stdout: 'Invalid storage: must be persistent or ram' };
				cmd += ' --storage ' + args.storage;
			}
			if (args.auto_update && length(args.auto_update)) {
				if (args.auto_update != '0' && args.auto_update != '1')
					return { code: -1, stdout: 'Invalid auto_update: must be 0 or 1' };
				cmd += ' --auto-update ' + args.auto_update;
			}

			return shell(cmd);
		}
	},

	do_install_version: {
		args: { version: '', source: '' },
		call: function(req) {
			let args = (req && req.args) ? req.args : {};
			if (!is_valid_version(args.version))
				return { code: -1, stdout: 'Invalid version format' };

			let cmd = 'tailscale-manager install-version ' + args.version;
			if (args.source && length(args.source)) {
				if (!VALID_SOURCES[args.source])
					return { code: -1, stdout: 'Invalid source: must be official or small' };
				cmd += ' --source ' + args.source;
			}

			return shell(cmd);
		}
	},

	do_update: {
		call: function() {
			return shell('tailscale-manager update --auto');
		}
	},

	do_uninstall: {
		call: function() {
			return shell('tailscale-manager uninstall --yes');
		}
	},

	get_latest_version: {
		call: function() {
			let bin_dir = find_bin_dir();
			let installed_source = get_installed_source(bin_dir);

			if (installed_source == 'official') {
				let r = shell("wget -T 5 -qO- 'https://pkgs.tailscale.com/stable/?mode=json' 2>/dev/null");
				if (r.code == 0 && r.stdout) {
					let data = json(r.stdout);
					if (data && data.TarballsVersion)
						return { version: data.TarballsVersion, source: 'official' };
				}
				return { version: null, source: null };
			}

			// small source or not yet installed — query GitHub only,
			// matching tailscale-manager get_small_latest_version() which
			// never falls back to official.
			let r = shell("wget -T 5 -qO- 'https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/latest' 2>/dev/null");
			if (r.code == 0 && r.stdout) {
				let data = json(r.stdout);
				if (data && data.tag_name) {
					let v = data.tag_name;
					if (substr(v, 0, 1) == 'v')
						v = substr(v, 1);
					return { version: v, source: 'small' };
				}
			}

			return { version: null, source: null };
		}
	},

	list_versions: {
		args: { limit: 0 },
		call: function(req) {
			let args = (req && req.args) ? req.args : {};
			let limit = clamp_int(args.limit, 1, 100);
			let r = shell('tailscale-manager list-versions ' + limit);
			if (r.code != 0)
				return { versions: [] };

			let lines = split(trim(r.stdout), '\n');
			let versions = [];
			for (let l in lines) {
				let v = trim(lines[l]);
				if (length(v) > 0)
					push(versions, v);
			}
			return { versions: versions };
		}
	},

	setup_firewall: {
		call: function() {
			let r = shell(
				'(' +
				'set -e;' +
				'TAILSCALE_MANAGER_SOURCE_ONLY=1;' +
				'LOG_FILE=/tmp/tailscale-fw-setup.log;' +
				'. /usr/bin/tailscale-manager;' +
				'setup_tailscale_interface;' +
				'setup_tailscale_firewall_zone;' +
				'/etc/init.d/network reload >/dev/null 2>&1 || { echo "Failed to reload network"; exit 1; };' +
				'/etc/init.d/firewall reload >/dev/null 2>&1 || { echo "Failed to reload firewall"; exit 1; };' +
				'echo done)'
			);
			return { success: (r.code == 0), stdout: r.stdout };
		}
	},

	sync_scripts: {
		call: function() {
			return shell('tailscale-manager sync-scripts');
		}
	}
};

return { 'luci.tailscale': methods };
