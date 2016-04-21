{% from "rsyslog/map.jinja" import rsyslog with context -%}
{% set install_from_source = rsyslog.get('install_from_source', False) -%}

{% if install_from_source -%}
include:
  - rsyslog.source
{% else -%}
rsyslog:
  pkg.installed:
    - name: {{ rsyslog.package }}
{% endif -%}

rsyslog-config:
  file.managed:
    - name: {{ rsyslog.config }}
    - template: jinja
    - source: {{ rsyslog.get('config_template' , 'salt://rsyslog/templates/rsyslog.conf.jinja') }}
    - context:
      config: {{ salt['pillar.get']('rsyslog', {}) }}
  service.running:
    - enable: True
    - name: {{ rsyslog.service }}
    - require:
      {% if install_from_source -%}
      - cmd: rsyslog
      {% else -%}
      - pkg: {{ rsyslog.package }}
      {% endif %}
    - watch:
      - file: {{ rsyslog.config }}

workdirectory:
  file.directory:
    - name: {{ rsyslog.workdirectory }}
    - user: {{ rsyslog.runuser }}
    - group: {{ rsyslog.rungroup }}
    - mode: 755
    - makedirs: True

{% for filename in salt['pillar.get']('rsyslog:custom', ["50-default.conf"]) %}
{% set basename = filename.split('/')|last %}
rsyslog_custom_{{basename}}:
  file.managed:
    - name: {{ rsyslog.custom_config_path }}/{{ basename|replace(".jinja", "") }}
    {% if basename != filename %}
    - source: {{ filename }}
    {% else %}
    - source: salt://rsyslog/files/{{ filename }}
    {% endif %}
    {% if filename.endswith('.jinja') %}
    - template: jinja
    {% endif %}
    - watch_in:
      - service: {{ rsyslog.service }}
{% endfor %}

