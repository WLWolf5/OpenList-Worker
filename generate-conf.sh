#!/bin/bash
# 严格模式：遇到错误立即退出，未定义变量报错，管道失败也会被捕获
set -euo pipefail

# 定义一个函数来更新配置项，防止重复代码
# 用法: update_config <key> <value> <config_file>
update_config() {
    local key="$1"
    local value="$2"
    local file="$3"
    # 使用 @ 作为 sed 分隔符以避免与路径中的特殊字符冲突
    sed -i "s#^${key} = .*#${key} = \"${value}\"#g" "$file"
}

# 定义一个函数来追加配置项（如果环境变量存在）
# 用法: append_if_set <env_var> <config_line> <config_file>
append_if_set() {
    local env_var="${!1:-}" # 获取环境变量的值，如果未设置则为空
    local line="$2"
    local file="$3"
    if [ -n "$env_var" ]; then
        echo "$line" >> "$file"
    fi
}

# 主逻辑
{
    cat > wrangler.toml << 'EOF'
compatibility_date = "2026-08-04"
compatibility_flags = ["nodejs_compat"]
main = "src/backend/worker.ts"
name = "openlist-tsworkers"
preview_urls = false
workers_dev = false

[assets]
binding = "ASSETS"
directory = "./dist"
run_worker_first = ["/", "/index.html"]

EOF

    if [ -n "${WORKER_NAME}" ]; then
        update_config "name" "$WORKER_NAME" wrangler.toml
    fi

    if [ "${ENABLE_LOG}" = true ]; then
        cat >> wrangler.toml << 'EOF'
[observability.logs]
enabled = true
head_sampling_rate = 1
invocation_logs = true
persist = true
[observability.traces]
enabled = true
head_sampling_rate = 1
persist = true
[observability.issue_detection]
enabled = true

EOF
    fi

    # 只有当 DB_DRIVER 为 "d1" 时才添加这个块
    if [ "$DB_DRIVER" == "d1" ]; then
        cat >> wrangler.toml << 'EOF'
[[d1_databases]]
binding = "DB"
database_name = "openlist"
database_id = ""

EOF
        # 在块内更新 database_id
        if [ -n "${D1_DATABASE_ID:-}" ]; then
            update_config "database_id" "$D1_DATABASE_ID" wrangler.toml
        fi
    fi

    if [ -n "${R2_BUCKET_NAME}" ]; then
        cat >> wrangler.toml << 'EOF'
[[r2_buckets]]
binding = "R2"
bucket_name = ""

EOF
        update_config "bucket_name" "$R2_BUCKET_NAME" wrangler.toml
    fi

    # 添加 [vars] 部分
    cat >> wrangler.toml << 'EOF'
[vars]
DB_CIPHER = "none"
DB_DRIVER = "auto"
DB_FORMAT = "map"
CACHE_DOWNLOAD_LINK = "false"
CACHE_DRIVER = "db"
CACHE_ENABLED = "true"
CACHE_EXCLUDE_DRIVERS = "virtual,alias,url_tree,strm,chunk"
CACHE_FILE_TREE = "true"
CACHE_LINK_TTL = "5"
CACHE_TTL = "0"
ENVIRONMENT = "production"
SINGLEFLIGHT = "auto"
EOF

    # 更新 [vars] 部分中已有的配置项
    update_config "DB_DRIVER" "$DB_DRIVER" wrangler.toml
    update_config "DB_CIPHER" "$DB_CIPHER" wrangler.toml
    update_config "DB_FORMAT" "$DB_FORMAT" wrangler.toml

    # 追加 [vars] 部分中可选的配置项
    append_if_set "MAX_UPLOAD" "MAX_UPLOAD = \"$MAX_UPLOAD\"" wrangler.toml
    append_if_set "MAX_UPPART" "MAX_UPPART = \"$MAX_UPPART\"" wrangler.toml
#    append_if_set "ALLOW_URLS" "ALLOW_URLS = \"$ALLOW_URLS\"" wrangler.toml

    # 处理密钥文件
    touch "/tmp/secret.env"
    append_if_set "ADMIN_PASS" "ADMIN_PASS=\"$ADMIN_PASS\"" "/tmp/secret.env"
    append_if_set "JWT_SECRET" "JWT_SECRET=\"$JWT_SECRET\"" "/tmp/secret.env"

    if ! [ -n "${JWT_SECRET}" ]; then
        JWT_SECRET=$(openssl rand -hex 16)
        echo "JWT_SECRET=\"$JWT_SECRET\"" >> "/tmp/secret.env"
    fi

    echo "wrangler.toml 生成成功"
}
