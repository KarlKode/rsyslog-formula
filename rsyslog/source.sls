{% from "rsyslog/map.jinja" import rsyslog as rl with context -%}

{% set use_sysvinit = rl.get('use_sysvinit', False) -%}
{% set use_systemd = rl.get('use_systemd', False) -%}
{% set build_options = rl.get('build_options', {}) -%}
{% set version = build_options.get('version', '8.18.0') -%}
{% set tarball_url = build_options.get('tarball_url', 'http://www.rsyslog.com/files/download/rsyslog/rsyslog-' + version + '.tar.gz') -%}
{% set checksum = build_options.get('checksum', 'sha256=94346237ecfa22c9f78cebc3f18d59056f5d9846eb906c75beaa7e486f02c695') -%}
{% set source = build_options.get('source_root', '/usr/local/src') -%}

{% set install_prefix = build_options.get('install_prefix', '/usr/local') -%}

{% set enable_items = build_options.get('enable', []) -%}
{% set disable_items = build_options.get('disable', []) -%}
{% set make_flags = build_options.get('make_flags', '') -%}

{% set service_name = rl.get('service', 'rsyslog') -%}
{% set service_enable = build_options.get('service_enable', True) -%}

{% set rsyslog_package = source + '/rsyslog-' + version + '.tar.gz' -%}
{% set rsyslog_source  = source + "/rsyslog-" + version -%}
{% set add_repository = build_options.get('add_repository', True) -%}

rsyslog_group:
  group.present:
    - name: {{ rl.rungroup }}

rsyslog_user:
  user.present:
    - name: {{ rl.runuser }}
    - groups:
      - {{ rl.rungroup }}
    - require:
      - group: rsyslog_group

{{ source }}:
  file.directory:
    - makedirs: True

{% if add_repository -%}
rsyslog-repository:
  pkgrepo.managed:
    - name: deb http://debian.adiscon.com/v8-stable wheezy/
    - file: /etc/apt/sources.list.d/rsyslog.list
    - keyid: AEF0CF8E
    - keyserver: keys.gnupg.net
    - require_in:
      - pkg: get-rsyslog

rsyslog-dev-repository:
  pkgrepo.managed:
    - name: deb-src http://debian.adiscon.com/v8-stable wheezy/
    - file: /etc/apt/sources.list.d/rsyslog.list
    - keyid: AEF0CF8E
    - keyserver: keys.gnupg.net
    - require_in:
      - pkg: get-rsyslog
{% endif -%}

get-rsyslog:
  pkg.installed:
    - names:
      {% for name, package in build_options.get('packages', {}).items() -%}
      {% if package -%}
      - {{ package }}
      {% endif -%}
      {% endfor %}
      {% for name in build_options.get('additional_packages', []) -%}
      - {{ name }}
      {% endfor %}
  file.managed:
    - name: {{ rsyslog_package }}
    - source: {{ tarball_url }}
    - source_hash: {{ checksum }}
    - require:
      - file: {{ source }}
  cmd.wait:
    - cwd: {{ source }}
    - name: tar --transform "s,^$(tar --list -zf rsyslog-{{ version }}.tar.gz | head -n 1),rsyslog-{{ version }}/," -zxf {{ rsyslog_package }}
    - require:
      - pkg: get-rsyslog
      - file: get-rsyslog
    - watch:
      - file: get-rsyslog

is-rsyslog-source-modified:
  cmd.run:
    - cwd: {{ source }}
    - stateful: True
    - names:
      - if [ ! -d "rsyslog-{{ version }}" ]; then
          echo "changed=yes comment='Tarball has not yet been extracted'";
          exit 0;
        fi;
        cd "rsyslog-{{ version }}";
        m=$(find . \! -name "build.*" -newer {{ install_prefix }}/sbin/rsyslogd -print -quit);
        r=$?;
        if [ x$r != x0 ]; then
          echo "changed=yes comment='binary file does not exist or other find error'";
          exit 0;
        fi;
        if [ x$m != "x" ]; then
          echo "changed=yes comment='source files are newer than binary'";
          exit 0;
        fi;
        echo "changed=no comment='source files are older than binary'"

rsyslog:
  cmd.wait:
    - cwd: {{ rsyslog_source }}
    - names:
      - (
        ./configure
        --prefix={{ install_prefix }}
        {%- for name in enable_items %}
        --enable-{{ name }}
        {%- endfor -%}
        {%- for name in disable_items -%}
        --disable-{{ name }}
        {%- endfor %}
        && make {{ make_flags }}
        && make install
        )
    - watch:
      - cmd: get-rsyslog
      - cmd: is-rsyslog-source-modified
    - require:
      - cmd: get-rsyslog
{% if use_sysvinit %}
  file:
    - managed
    - template: jinja
    - name: /etc/init.d/{{ service_name }}
    - source: salt://rsyslog/templates/rsyslog.init.jinja
    - user: root
    - group: root
    - mode: 0755
    - context:
      service_name: {{ service_name }}
      sbin_dir: {{ sbin_dir }}
      pid_path: {{ pid_path }}
{% elif use_systemd %}
  file:
    - managed
    - template: jinja
    - name: /lib/systemd/system/{{ service_name }}.service
    - source: salt://rsyslog/templates/rsyslog.service.jinja
    - user: root
    - group: root
    - mode: 0755
    - context:
      service_name: {{ service_name }}
      prefix: {{ install_prefix }}
{% endif %}
  service:
{% if service_enable %}
    - running
    - enable: True
    - restart: True
{% else %}
    - dead
    - enable: False
{% endif %}
    - name: {{ service_name }}
    - watch:
      - cmd: rsyslog
      - file: {{ rl.config }}
    - require:
      - cmd: rsyslog
      - file: {{ rl.config }}

