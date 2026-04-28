import os
import requests
import json
import base64
from urllib.parse import urlparse

def login(base_url, username, password):
    session = requests.Session()
    headers = {'User-Agent': 'Mozilla/5.0', 'content-type': 'application/json'}

    response = session.post(f"{base_url}/api/login", json={'username': username, 'password': password}, headers=headers)
    if response.json().get('code') != 'SUCCESS':
        raise Exception("登录失败")

    token = response.json()["data"]["token"]
    headers['Authorization'] = token
    return session, headers

def get_connected_nodes(session, headers, base_url):
    response = session.get(f"{base_url}/api/touch", headers=headers, timeout=10)
    data = response.json()

    connected = data['data']['touch']['connectedServer']
    subscriptions = data['data']['touch']['subscriptions']

    connected_nodes = []
    for conn in connected:
        node_id = conn['id']
        sub_index = conn['sub']
        outbound = conn.get('outbound', 'proxy')

        if sub_index < len(subscriptions):
            sub = subscriptions[sub_index]
            for server in sub.get('servers', []):
                if server['id'] == node_id:
                    connected_nodes.append({
                        'id': node_id,
                        'sub_index': sub_index,
                        'name': server.get('name'),
                        'address': server.get('address'),
                        'net': server.get('net'),
                        'outbound': outbound
                    })
                    break
    return connected_nodes

def parse_subscription(content):
    share_links = []
    lines = content.strip().split('\n')

    for line in lines:
        line = line.strip()
        if not line:
            continue

        if line.startswith('vmess://'):
            try:
                config_b64 = line[8:]
                config_json = base64.b64decode(config_b64).decode('utf-8')
                config = json.loads(config_json)
                share_links.append({
                    'protocol': 'vmess',
                    'name': config.get('ps', ''),
                    'address': config.get('add', ''),
                    'port': config.get('port', ''),
                    'link': line
                })
            except:
                pass

        elif line.startswith('vless://'):
            share_links.append({
                'protocol': 'vless',
                'name': '',
                'address': '',
                'port': '',
                'link': line
            })

        elif line.startswith('trojan://'):
            try:
                parsed = urlparse(line)
                netloc = parsed.netloc
                if '@' in netloc:
                    addr_part = netloc.split('@')[1]
                    host_port = addr_part.rsplit(':', 1) if ':' in addr_part else (addr_part, '')
                    share_links.append({
                        'protocol': 'trojan',
                        'name': '',
                        'address': host_port[0],
                        'port': host_port[1] if len(host_port) > 1 else '',
                        'link': line
                    })
            except:
                pass

        elif line.startswith('ss://'):
            share_links.append({
                'protocol': 'ss',
                'name': '',
                'address': '',
                'port': '',
                'link': line
            })

    return share_links

def normalize_string(s):
    if not s:
        return ''
    return s.replace(' ', '').replace('-', '').replace('_', '').lower()

def strings_similar(s1, s2, threshold=0.6):
    if not s1 or not s2:
        return False
    s1_norm = normalize_string(s1)
    s2_norm = normalize_string(s2)
    if s1_norm in s2_norm or s2_norm in s1_norm:
        return True
    return False

def load_existing_links(output_file):
    existing_links = set()
    if os.path.exists(output_file):
        with open(output_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line:
                    existing_links.add(line)
    return existing_links

def append_link(link, output_file, max_lines=500):
    existing_links = load_existing_links(output_file)

    if link in existing_links:
        return False

    all_links = list(existing_links) + [link]
    if len(all_links) > max_lines:
        all_links = all_links[-max_lines:]

    with open(output_file, 'w', encoding='utf-8') as f:
        for l in all_links:
            f.write(l + '\n')

    return True

def process_subscription(sub_index, sub, connected_nodes, session, output_file, max_lines=500):
    matched_count = 0
    matched_node_ids = set()

    sub_address = sub.get('address')
    if not sub_address:
        return 0

    try:
        print(f"\n正在加载订阅源: {sub.get('remarks', f'订阅 {sub_index}')}")
        sub_response = session.get(sub_address, timeout=15)
        content = sub_response.text
        share_links = parse_subscription(content)
        print(f"  -> 已加载 {len(share_links)} 个节点")
    except Exception as e:
        print(f"  -> 加载失败: {str(e)}")
        return 0

    # 获取该订阅源下已连接的节点
    sub_connected_nodes = [
        node for node in connected_nodes
        if node['sub_index'] == sub_index and node['id'] not in matched_node_ids
    ]

    print(f"  -> 该订阅源下已连接 {len(sub_connected_nodes)} 个节点")

    # 匹配该订阅源下的已连接节点
    for conn_node in sub_connected_nodes:
        if conn_node['id'] in matched_node_ids:
            continue

        conn_name = conn_node['name']
        conn_address = conn_node['address']

        best_match = None
        best_match_quality = 0

        for link_info in share_links:
            link = link_info['link']
            link_name = link_info['name']
            link_address = link_info['address']

            name_similar = strings_similar(conn_name, link_name)
            addr_similar = strings_similar(conn_address, link_address)

            quality = 0
            if name_similar and addr_similar:
                quality = 3
            elif name_similar:
                quality = 2
            elif addr_similar:
                quality = 1
            elif conn_name in link_name or link_name in conn_name:
                quality = 1.5

            if quality > best_match_quality:
                best_match_quality = quality
                best_match = {
                    'node': conn_node,
                    'link': link,
                    'quality': quality
                }

        if best_match and best_match['quality'] >= 1:
            matched_node_ids.add(conn_node['id'])
            print(f"    匹配成功: {conn_node['name']} (质量: {best_match['quality']})")
            print(f"      地址: {conn_node['address']}")

            is_new = append_link(best_match['link'], output_file, max_lines)
            if is_new:
                matched_count += 1
                print(f"      -> 已写入新链接")
            else:
                print(f"      -> 链接已存在")

    return matched_count


def main():
    config_content=open('v2raya_auth.json',"r",encoding="utf-8")
    config = json.load(config_content)

    base_url = config['host']
    username = config['username']
    password = config['password']

    print(f"正在连接: {base_url}")
    print(f"用户名: {username}\n")

    session, headers = login(base_url, username, password)
    print("登录成功\n")

    connected_nodes = get_connected_nodes(session, headers, base_url)
    print(f"已连接 {len(connected_nodes)} 个节点\n")

    response = session.get(f"{base_url}/api/touch", headers=headers, timeout=10)
    data = response.json()
    subscriptions = data['data']['touch']['subscriptions']

    output_file = 'proxy_subscriptions.txt'
    total_matched = 0

    print("开始循环处理每个订阅源...")
    for sub_index, sub in enumerate(subscriptions):
        matched_count = process_subscription(sub_index, sub, connected_nodes, session, output_file, max_lines=500)
        total_matched += matched_count

    print(f"\n共写入 {total_matched} 个新链接到: {output_file}")

if __name__ == '__main__':
    main()