# Clear NDR Templates

> **Note**: This repository contains configuration templates for [stamusctl](https://github.com/StamusNetworks/stamusctl). For CLI tool issues, please report them to the main stamusctl repository.

## Overview

This repository provides public templates for deploying Stamus Networks security solutions using `stamusctl`. Templates are consumed by the CLI tool to generate Docker Compose configurations and related deployment files.

For comprehensive documentation, visit [https://docs.clearndr.io/](https://docs.clearndr.io/).

## Available Templates

### Clear NDR

The `clearndr` template deploys Clear NDR Community with the following components:

- **Suricata**: Network intrusion detection system
- **Scirius**: Web-based rule management and event analysis
- **OpenSearch**: Search and analytics engine
- **OpenSearch Dashboards**: Data visualization interface
- **Arkime**: Network packet capture and analysis
- **Evebox**: Event and alert management
- **NGINX**: Web proxy and SSL termination

## Template Structure

```
data/
├── clearndr/               # Clear NDR template
│   ├── compose.yml         # Main Docker Compose template
│   ├── config.yaml         # Template configuration
│   └── [components]/       # Component-specific configs
└── tests/                  # Test configurations
```

## Configuration Values

### Clear NDR Template

| Key                                 | Default                                                                  | Usage                                                                                                                            |
| ----------------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| arkime.openport                     | false                                                                    | Open port for Arkime Viewer ?                                                                                                    |
| cron.logrotate.enabled              | true                                                                     | Enable logrotate for Suricata logs                                                                                               |
| cron.logrotate.period               | daily                                                                    | Logrotate period (`1min`, `daily`, `weekly`, `monthly`)                                                                          |
| cron.updatesurirules.enabled        | true                                                                     | Enable automatic update of Suricata rules                                                                                        |
| cron.updatesurirules.period         | daily                                                                    | Update period (`1min`, `daily`, `weekly`, `monthly`)                                                                             |
| evebox.version                      | master                                                                   | Evebox version to install                                                                                                        |
| globals.restartmode                 | unless-stopped                                                           | Restart mode for all services                                                                                                    |
| globals.proxy.enabled               | false                                                                    | Enable proxy support for all services                                                                                            |
| globals.proxy.http                  |                                                                          | HTTP proxy URL (e.g., http://proxy.company.com:3128)                                                                             |
| globals.proxy.https                 |                                                                          | HTTPS proxy URL (e.g., http://proxy.company.com:3128)                                                                            |
| globals.proxy.no_proxy              | localhost,127.0.0.1,opensearch,opensearch-dashboards,scirius,scout,nginx | Comma-separated list of hosts that should not use proxy                                                                          |
| nginx.ssl.certname                  | scirius.crt                                                              | Name of the certificate file. Used only if ssl.enabled is true.                                                                  |
| nginx.ssl.enabled                   | true                                                                     | Enable SSL for NGINX                                                                                                             |
| nginx.ssl.folder                    |                                                                          | Folder on host containing SSL certificates. If set, disable automatic generation of self-signed certificates. Use absolute path. |
| nginx.ssl.keyname                   | scirius.key                                                              | Name of the private key file. Used only if ssl.enabled is true.                                                                  |
| opensearch.dashboards.openport      | true                                                                     | Expose OpenSearch Dashboards port                                                                                                |
| opensearch.datapath                 | opensearch-data                                                          | Data path on host to store OpenSearch data                                                                                       |
| opensearch.ism.delete_min_index_age | 15d                                                                      | Minimum index age before transitioning to delete state                                                                           |
| opensearch.ism.warm_min_index_age   | 7d                                                                       | Minimum index age before transitioning to warm state                                                                             |
| opensearch.memory                   | 2g                                                                       | Memory limit for OpenSearch                                                                                                      |
| opensearch.openport                 | false                                                                    | Expose OpenSearch port                                                                                                           |
| rabbitmq.openport                   | false                                                                    | Expose RabbitMQ port                                                                                                             |
| scirius.celery.beat.restart         | unless-stopped                                                           | Celery beat restart mode                                                                                                         |
| scirius.celery.worker.restart       | unless-stopped                                                           | Celery worker restart mode                                                                                                       |
| scirius.debug                       | false                                                                    | Enable debug mode                                                                                                                |
| scirius.registry                    | ghcr.io/stamusnetworks/scirius                                           | Image registry where to find scirius image                                                                                       |
| scirius.version                     | clear-ndr-rc3                                                            | Scirius version to install                                                                                                       |
| suricata.additionalconfig           |                                                                          | Additional configuration for Suricata                                                                                            |
| suricata.homenet                    | 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12                                  | Home network CIDR ranges                                                                                                         |
| suricata.interfaces                 |                                                                          | List of interfaces to monitor                                                                                                    |
| suricata.unixsocket.enabled         | false                                                                    | Enable Unix Socket Output for Suricata Eve logs ?                                                                                |
| Key                                 | Default                                                                  | Usage                                                                                                                            |

## Template Variables

Templates use Go template syntax with the following top-level variables:

| Variable           | Description                                      |
| ------------------ | ------------------------------------------------ |
| .Values            | User-provided configuration values               |
| .Release.name      | Name of the release                              |
| .Release.user      | User creating the release                        |
| .Release.group     | User's group creating the release                |
| .Release.location  | Release deployment location                      |
| .Release.isUpgrade | Whether the release is an upgrade                |
| .Release.isInstall | Whether the release is an install                |
| .Release.service   | Service creating the release (stamusctl/stamusd) |
| .Template.name     | Name of the current template                     |
| .Release.version   | Version of the current template                  |

## Usage

Templates are consumed by `stamusctl`:

```bash
# Initialize with default template (clearndr)
stamusctl compose init

# Initialize with custom values
stamusctl compose init suricata.interfaces=eth0 opensearch.memory=4g

# Use specific template version
stamusctl compose init --version v1.2.0

# View available configuration keys
stamusctl config keys --markdown
```

## Development

### Template Development

Templates use Go's `text/template` package with [Sprig](https://github.com/Masterminds/sprig) functions.

**Key Guidelines:**

- Use descriptive configuration keys
- Provide sensible defaults
- Include comprehensive documentation
- Test with various configuration scenarios

### Testing

Test templates locally:

```bash
# Build and test template
make -C bin/tests

# Test specific configuration
stamusctl compose init --template ./data/clearndr suricata.interfaces=eth0
```

## Contributing

1. **Fork the repository**
2. **Create a feature branch**
3. **Make your changes**
4. **Test thoroughly**
5. **Submit a pull request**

### Issues

Report template-related issues to this repository:

- Template configuration problems
- Missing template features
- Documentation improvements
- New template requests

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See the [LICENSE](LICENSE) file for details.

## Support

- **Documentation**: [https://docs.clearndr.io/](https://docs.clearndr.io/)
- **Issues**: [GitHub Issues](https://github.com/StamusNetworks/stamusctl-public-templates/issues)
- **Main CLI Tool**: [stamusctl](https://github.com/StamusNetworks/stamusctl)
- **Professional Support**: [Stamus Networks](https://www.stamus-networks.com/)
