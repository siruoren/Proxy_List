import json
import os
import requests
import time
import base64

def load_config():
    with open("v2raya_auth.json", "r", encoding='utf8') as f:
        config = json.load(f)
    if "node_params" not in config:
        config["node_params"] = {
            "vmess": {"uuid": "d13fc2f5-3e05-4795-81eb-44143a09e552", "alterId": 0},
            "ss": {"method": "aes-256-gcm", "password": "your_ss_password"},
            "trojan": {"password": "your_trojan_password"},
            "vless": {"uuid": "d13fc2f5-3e05-4795-81eb-44143a09e552"}
        }
    return config

def login(config):
    url = f"{config['host']}/api/login"
    payload = {"username": config['username'], "password": config['password']}
    headers = {"content-type": "application/json"}
    response = requests.post(url, json=payload, headers=headers)
    return response.json()["data"]["token"]

def get_status(host, token):
    url = f"{host}/api/touch"
    response = requests.get(url, headers={"Authorization": token})
    return response.json()

def get_connected_servers(status):
    return status["data"]["touch"]["connectedServer"]

def build_subscription_urls(connected_servers, status, config):
    subscription_urls = []
    subscriptions = status["data"]["touch"]["subscriptions"]
    vmess_uuid = config["node_params"]["vmess"]["uuid"]
    ss_password = config["node_params"]["ss"]["password"]
    trojan_password = config["node_params"]["trojan"]["password"]
    vless_uuid = config["node_params"]["vless"]["uuid"]

    for connect in connected_servers:
        if connect.get("_type") == "subscriptionServer":
            sub_id = connect.get("sub")
            node_id = connect.get("id")

            for sub in subscriptions:
                if sub.get("id") == sub_id + 1:
                    for server in sub.get("servers", []):
                        if server.get("id") == node_id:
                            net_field = server.get('net', '')
                            protocol = net_field.split('(')[0].lower()

                            if protocol == 'vmess':
                                address = server.get("address", "")
                                add = address
                                port = server.get("port")
                                if ':' in address:
                                    parts = address.split(':')
                                    add = ':'.join(parts[:-1])
                                    port = parts[-1]

                                vmess_config = {
                                    "ps": server.get("name"),
                                    "add": add,
                                    "port": port or server.get("port", ""),
                                    "id": vmess_uuid,
                                    "aid": config["node_params"]["vmess"]["alterId"],
                                    "scy": "auto",
                                    "net": net_field.split('(')[1].rstrip(')') if '(' in net_field else 'tcp',
                                    "type": server.get("type", ""),
                                    "host": server.get("host", ""),
                                    "path": server.get("path", ""),
                                    "tls": server.get("tls", ""),
                                    "allowInsecure": False,
                                    "quicSecurity": "",
                                    "v": "2",
                                    "protocol": "vmess"
                                }
                                vmess_json = json.dumps(vmess_config, ensure_ascii=False)
                                vmess_b64 = base64.b64encode(vmess_json.encode('utf-8')).decode('utf-8')
                                subscription_urls.append(f"vmess://{vmess_b64}")

                            elif protocol == 'trojan':
                                trojan_url = f"trojan://{trojan_password}@{server.get('address')}:{server.get('port')}?security={server.get('tls', 'tls')}&sni={server.get('sni', '')}&type={server.get('type', 'tcp')}&path={server.get('path', '')}#{server.get('name')}"
                                subscription_urls.append(trojan_url)

                            elif protocol == 'ss':
                                method = net_field.split('(')[1].rstrip(')') if '(' in net_field else config["node_params"]["ss"]["method"]
                                ss_config = f"{method}:{ss_password}@{server.get('address')}:{server.get('port')}"
                                ss_b64 = base64.b64encode(ss_config.encode('utf-8')).decode('utf-8')
                                subscription_urls.append(f"ss://{ss_b64}#{server.get('name')}")

                            elif protocol == 'vless':
                                vless_url = f"vless://{vless_uuid}@{server.get('address')}:{server.get('port')}?security={server.get('tls', 'tls')}&sni={server.get('sni', '')}&type={net_field.split('(')[1].rstrip(')') if '(' in net_field else 'tcp'}&path={server.get('path', '')}#{server.get('name')}"
                                subscription_urls.append(vless_url)

    return subscription_urls

def write_subscription_file(subscription_urls, filename="proxy_subscriptions.txt"):
    existing_urls = []
    if os.path.exists(filename):
        with open(filename, "r", encoding='utf-8') as f:
            existing_urls = [line.strip() for line in f if line.strip()]

    existing_set = set(existing_urls)
    new_urls = [url for url in subscription_urls if url not in existing_set]

    all_urls = existing_urls + new_urls
    urls_to_write = all_urls[-500:] if len(all_urls) > 500 else all_urls

    with open(filename, "w", encoding='utf-8') as f:
        for url in urls_to_write:
            f.write(url + "\n")

    print(f"新增 {len(new_urls)} 条订阅地址，已写入文件: {filename}, 共 {len(urls_to_write)} 条")

def main():
    config = load_config()
    token = login(config)
    print(f"登录成功，获取到token: {token[:20]}...")

    status = get_status(config['host'], token)
    print("获取服务状态成功")

    connected_servers = get_connected_servers(status)
    print(f"已连接的节点数量: {len(connected_servers)}")

    subscription_urls = build_subscription_urls(connected_servers, status, config)
    print(f"生成的订阅地址数量: {len(subscription_urls)}")

    write_subscription_file(subscription_urls)

if __name__ == "__main__":
    main()
