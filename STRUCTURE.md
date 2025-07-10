clickhouse-cluster/
├── stacks/
│   ├── docker-stack.local.yml
│   ├── docker-stack.prod.yml
│   └── .env.example
├── config/
│   ├── clickhouse/
│   │   ├── local/
│   │   │   ├── config.xml
│   │   │   ├── users.xml
│   │   │   ├── cluster-config.xml
│   │   │   └── remote-servers.xml
│   │   └── production/
│   │       ├── config.xml
│   │       ├── users.xml
│   │       ├── cluster-config.xml
│   │       └── remote-servers.xml
│   └── keeper/
│       ├── local/
│       │   └── keeper-config.xml
│       └── production/
│           └── keeper-config.xml
├── secrets/
│   ├── ssl/
│   │   ├── local/
│   │   │   ├── ca.crt
│   │   │   ├── clickhouse-server.crt
│   │   │   ├── clickhouse-server.key
│   │   │   ├── keeper.crt
│   │   │   └── keeper.key
│   │   └── production/
│   │       ├── ca.crt
│   │       ├── clickhouse-server.crt
│   │       ├── clickhouse-server.key
│   │       ├── keeper.crt
│   │       └── keeper.key
│   ├── passwords/
│   │   ├── local/
│   │   │   └── clickhouse-password.txt
│   │   └── production/
│   │       └── clickhouse-password.txt
│   └── .gitignore
├── scripts/
│   ├── generate-certs.sh
│   ├── deploy-local.sh
│   ├── deploy-prod.sh
│   ├── init-cluster.sh
│   └── health-check.sh
└── docs/
    ├── deployment.md
    └── ssl-configuration.md