import os
import requests
import json
import base64
import difflib
from urllib.parse import urlparse, unquote

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

        if sub_index < 0:
            print(f"  跳过手动添加的服务器 id={node_id}（无订阅源）")
            continue

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
    return connected_nodes, subscriptions

def parse_subscription(content):
    share_links = []
    lines = content.strip().split('\n')

    # 检测是否为 base64 编码的订阅内容
    has_protocol_prefix = any(
        line.strip().startswith(('vmess://', 'vless://', 'trojan://', 'ss://', 'hysteria2://', 'hy2://'))
        for line in lines if line.strip()
    )

    if not has_protocol_prefix:
        try:
            decoded = base64.b64decode(content.strip() + '===').decode('utf-8')
            lines = decoded.strip().split('\n')
            print(f"  -> 检测到 base64 编码内容，已解码")
        except Exception:
            lines = content.strip().split('\n')

    for line in lines:
        line = line.strip()
        if not line:
            continue

        if line.startswith('vmess://'):
            try:
                config_b64 = line[8:]
                padding = 4 - len(config_b64) % 4
                if padding != 4:
                    config_b64 += '=' * padding
                config_json = base64.b64decode(config_b64).decode('utf-8')
                config = json.loads(config_json)
                share_links.append({
                    'protocol': 'vmess',
                    'name': config.get('ps', ''),
                    'address': config.get('add', ''),
                    'port': str(config.get('port', '')),
                    'link': line
                })
            except Exception:
                pass

        elif line.startswith('vless://'):
            try:
                parsed = urlparse(line)
                name = unquote(parsed.fragment) if parsed.fragment else ''
                address = parsed.hostname or ''
                port = str(parsed.port) if parsed.port else ''
                share_links.append({
                    'protocol': 'vless',
                    'name': name,
                    'address': address,
                    'port': port,
                    'link': line
                })
            except Exception:
                pass

        elif line.startswith('trojan://'):
            try:
                parsed = urlparse(line)
                name = unquote(parsed.fragment) if parsed.fragment else ''
                address = parsed.hostname or ''
                port = str(parsed.port) if parsed.port else ''
                share_links.append({
                    'protocol': 'trojan',
                    'name': name,
                    'address': address,
                    'port': port,
                    'link': line
                })
            except Exception:
                pass

        elif line.startswith('ss://'):
            try:
                name = ''
                line_for_parse = line
                if '#' in line:
                    frag_start = line.rindex('#')
                    name = unquote(line[frag_start + 1:])
                    line_for_parse = line[:frag_start]

                ss_content = line_for_parse[5:]  # 去掉 'ss://'
                address = ''
                port = ''

                if '@' in ss_content:
                    # SIP002 格式: ss://base64(method:password)@address:port
                    at_idx = ss_content.rindex('@')
                    addr_port = ss_content[at_idx + 1:]
                    if addr_port.startswith('['):
                        # IPv6 地址
                        bracket_end = addr_port.index(']')
                        address = addr_port[1:bracket_end]
                        port = addr_port[bracket_end + 2:] if bracket_end + 2 < len(addr_port) else ''
                    elif ':' in addr_port:
                        address, port = addr_port.rsplit(':', 1)
                    else:
                        address = addr_port
                else:
                    # 传统格式: ss://base64(method:password@address:port)
                    try:
                        padding = 4 - len(ss_content) % 4
                        if padding != 4:
                            ss_content_padded = ss_content + '=' * padding
                        else:
                            ss_content_padded = ss_content
                        decoded = base64.b64decode(ss_content_padded).decode('utf-8')
                        if '@' in decoded:
                            _, addr_port = decoded.rsplit('@', 1)
                            if addr_port.startswith('['):
                                bracket_end = addr_port.index(']')
                                address = addr_port[1:bracket_end]
                                port = addr_port[bracket_end + 2:] if bracket_end + 2 < len(addr_port) else ''
                            elif ':' in addr_port:
                                address, port = addr_port.rsplit(':', 1)
                            else:
                                address = addr_port
                    except Exception:
                        pass

                share_links.append({
                    'protocol': 'ss',
                    'name': name,
                    'address': address,
                    'port': port,
                    'link': line
                })
            except Exception:
                pass

        elif line.startswith('hysteria2://') or line.startswith('hy2://'):
            try:
                prefix_len = len('hysteria2://') if line.startswith('hysteria2://') else len('hy2://')
                rest = line[prefix_len:]
                # 构造标准 URL 以便 urlparse 解析
                parsed = urlparse('http://' + rest)
                name = ''
                if '#' in rest:
                    name = unquote(rest.split('#')[-1])
                address = parsed.hostname or ''
                port = str(parsed.port) if parsed.port else ''
                share_links.append({
                    'protocol': 'hysteria2',
                    'name': name,
                    'address': address,
                    'port': port,
                    'link': line
                })
            except Exception:
                pass

    return share_links

def normalize_string(s):
    if not s:
        return ''
    return s.replace(' ', '').replace('-', '').replace('_', '').lower()

def strings_similar(s1, s2, threshold=0.5):
    if not s1 or not s2:
        return False
    s1_norm = normalize_string(s1)
    s2_norm = normalize_string(s2)
    if not s1_norm or not s2_norm:
        return False
    if s1_norm in s2_norm or s2_norm in s1_norm:
        return True
    ratio = difflib.SequenceMatcher(None, s1_norm, s2_norm).ratio()
    return ratio >= threshold

def load_existing_links(output_file):
    existing_links = set()
    if os.path.exists(output_file):
        with open(output_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line:
                    existing_links.add(line)
    return existing_links

def append_link(link, output_file):
    existing_links = load_existing_links(output_file)

    if link in existing_links:
        return False

    with open(output_file, 'a', encoding='utf-8') as f:
        f.write(link + '\n')

    return True

def process_subscription(sub_index, sub, connected_nodes, session, output_file, single_max=50):
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

    sub_connected_nodes = [
        node for node in connected_nodes
        if node['sub_index'] == sub_index and node['id'] not in matched_node_ids
    ]

    print(f"  -> 该订阅源下已连接 {len(sub_connected_nodes)} 个节点")

    unmatched_nodes = []

    for conn_node in sub_connected_nodes:
        if conn_node['id'] in matched_node_ids:
            continue

        if matched_count >= single_max:
            print(f"    已达到单个订阅最大 {single_max} 个链接限制，跳过")
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

            is_new = append_link(best_match['link'], output_file)
            if is_new:
                matched_count += 1
                print(f"      -> 已写入新链接")
            else:
                print(f"      -> 链接已存在")
        else:
            unmatched_nodes.append(conn_node)

    # 对未匹配的节点，尝试通过端口+协议组合进行二次匹配
    for conn_node in unmatched_nodes:
        if conn_node['id'] in matched_node_ids:
            continue
        if matched_count >= single_max:
            break

        conn_name = conn_node['name']
        conn_address = conn_node['address']
        conn_net = conn_node.get('net', '')

        best_match = None
        best_match_quality = 0

        for link_info in share_links:
            link = link_info['link']
            link_name = link_info['name']
            link_address = link_info['address']
            link_port = link_info.get('port', '')
            link_protocol = link_info['protocol']

            # 二次匹配：地址精确匹配 或 地址模糊匹配+端口匹配
            addr_exact = conn_address and link_address and conn_address == link_address
            addr_fuzzy = strings_similar(conn_address, link_address, threshold=0.7)
            port_match = conn_net and link_port and str(conn_net) == str(link_port)

            quality = 0
            if addr_exact:
                quality = 4
            elif addr_fuzzy and port_match:
                quality = 3
            elif addr_fuzzy:
                quality = 2
            elif port_match and strings_similar(conn_name, link_name, threshold=0.3):
                quality = 1

            if quality > best_match_quality:
                best_match_quality = quality
                best_match = {
                    'node': conn_node,
                    'link': link,
                    'quality': quality
                }

        if best_match and best_match['quality'] >= 1:
            matched_node_ids.add(conn_node['id'])
            print(f"    二次匹配成功: {conn_node['name']} (质量: {best_match['quality']})")
            print(f"      地址: {conn_node['address']}")

            is_new = append_link(best_match['link'], output_file)
            if is_new:
                matched_count += 1
                print(f"      -> 已写入新链接")
            else:
                print(f"      -> 链接已存在")
        else:
            print(f"    未匹配: {conn_node['name']} (地址: {conn_node['address']})")

    return matched_count


def main():
    with open('v2raya_auth.json', 'r', encoding='utf-8') as f:
        config = json.load(f)

    base_url = config['host']
    username = config['username']
    password = config['password']

    print(f"正在连接: {base_url}")
    print(f"用户名: {username}\n")

    session, headers = login(base_url, username, password)
    print("登录成功\n")

    connected_nodes, subscriptions = get_connected_nodes(session, headers, base_url)
    print(f"已连接 {len(connected_nodes)} 个节点\n")

    output_file = 'proxy_subscriptions.txt'
    total_matched = 0

    print("开始循环处理每个订阅源...")
    for sub_index, sub in enumerate(subscriptions):
        matched_count = process_subscription(sub_index, sub, connected_nodes, session, output_file)
        total_matched += matched_count

    print(f"\n共写入 {total_matched} 个新链接到: {output_file}")
    with open(output_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    if len(lines) > 500:
        lines = lines[-500:]
        with open(output_file, 'w', encoding='utf-8') as f:
            f.writelines(lines)
    print(f"当前文件共 {len(lines)} 行")

if __name__ == '__main__':
    main()