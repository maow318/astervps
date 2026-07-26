# aster-agent

被监控机器上运行的探针端。以 HTTPS + Bearer Token 暴露本机指标,由 Aster.app 主动轮询拉取;自身不向外发起任何连接。

## 构建

```sh
cd agent
go build -o aster-agent .        # 本机架构
make build-all                   # dist/ 下产出 linux-amd64 / linux-arm64 / darwin-arm64
```

## 参数

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `--listen` | `:9977` | HTTPS 监听地址 |
| `--token` | 必填 | Bearer 认证 token,由 Aster.app 添加机器时生成 |
| `--history-minutes` | `360` | 内存历史缓冲保留时长(30 秒一个采样点) |
| `--state-dir` | root:`/var/lib/aster-agent`;否则用户配置目录下 `aster-agent` | TLS 证书存放目录,必须可持久化,否则重启后指纹变化会被 App 拒绝 |
| `--cert` / `--key` | 自动生成 | 显式指定证书/私钥路径(PEM) |

首次启动自动生成自签 ECDSA P-256 证书,并在日志打印 `TLS SHA-256 fingerprint`,供 App 端 TOFU 确认比对。

## systemd 部署

```ini
# /etc/systemd/system/aster-agent.service
[Unit]
Description=Aster Agent
After=network-online.target

[Service]
ExecStart=/usr/local/bin/aster-agent --listen :9977 --token <TOKEN>
Restart=always

[Install]
WantedBy=multi-user.target
```

```sh
systemctl daemon-reload && systemctl enable --now aster-agent
journalctl -u aster-agent | grep fingerprint   # 查看指纹
```

## 手动安装(无脚本)

1. `make build-all` 后把对应架构二进制 `scp` 到服务器 `/usr/local/bin/aster-agent`,`chmod 755`;
2. 写入上述 systemd unit(替换 token)并启动;
3. 在 Aster.app"添加机器"里填入 `https://<服务器IP>:9977` 与该 token,确认指纹。

接口契约见 [docs/aster-protocol.md](../docs/aster-protocol.md)。
