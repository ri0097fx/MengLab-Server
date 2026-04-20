# 踏み台PCハードニング

## 必須

```bash
ssh-keygen -t ed25519 -f ~/.ssh/relay_tunnel_ed25519 -C "relay-tunnel-only"
chmod 600 ~/.ssh/relay_tunnel_ed25519
```

`~relay_tunnel/.ssh/authorized_keys`:

```text
restrict,port-forwarding,permitlisten="127.0.0.1:28081",permitopen="192.168.50.138:80",no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA... relay-tunnel-only
```

`/etc/ssh/sshd_config`:

```text
AllowTcpForwarding yes
GatewayPorts no
PasswordAuthentication no
PermitRootLogin no
```

```bash
sudo systemctl restart sshd
```

## 起動

```bash
RELAY_USER=relay_tunnel \
RELAY_SSH_KEY=~/.ssh/relay_tunnel_ed25519 \
RELAY_HOST=172.24.160.42 \
RELAY_SSH_PORT=20002 \
REMOTE_REVERSE_PORT=28081 \
TARGET_HOST=192.168.50.138 \
TARGET_PORT=80 \
./keep_reverse_tunnel.sh
```
