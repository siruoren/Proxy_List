import json
import requests
import logging
import base64

logging.basicConfig(level=logging.INFO, format='%(message)s')

CONFIG = {}
HOST = ""
TOKEN = ""

def get_subscription_content(sub_address):
    '''获取订阅地址的内容'''
    try:
        response = requests.get(sub_address, timeout=15)
        response.raise_for_status()
        return response.text
    except Exception as e:
        logging.error(f"获取订阅内容失败: {e}")
        return ""

def filter_proxy_content(content):
    '''过滤订阅内容，只保留代理信息'''    
    #print(content)
    
    lines = content.strip().split('\n')
    proxy_lines = []
    
    # 先尝试直接过滤
    for line in lines:
        line = line.strip()
        if line and not line.startswith('#'):
            # 检查是否是代理地址格式
            if line.startswith(('vmess://', 'ss://', 'ssr://', 'trojan://', 'vless://')):
                proxy_lines.append(line)
    
    # 如果没有找到代理信息，尝试对整个内容进行 Base64 解码
    has_proxy = any(line.startswith(('vmess://', 'ss://', 'ssr://', 'trojan://', 'vless://')) for line in lines if line.strip() and not line.strip().startswith('#'))
    if not has_proxy:
        try:
            # 处理可能的 URL 安全 Base64 编码
            content_for_decode = content.replace('-', '+').replace('_', '/')
            # 补充 Base64 填充
            padding = '=' * ((4 - len(content_for_decode) % 4) % 4)
            content_for_decode = content_for_decode + padding
            # 解码
            decoded_content = base64.b64decode(content_for_decode).decode('utf-8')
            #print(decoded_content)
            #exit()
            
            # 再次过滤解码后的内容
            decoded_lines = decoded_content.strip().split('\n')
            for line in decoded_lines:
                line = line.strip()
                if line and not line.startswith('#'):
                    #if line.startswith(('vmess://', 'ss://', 'ssr://', 'trojan://', 'vless://')):
                   proxy_lines.append(line)
        except Exception as e:
            logging.error(f"Base64 解码失败: {e}")
            pass

    return proxy_lines

def load_config():
    global CONFIG, HOST
    with open("v2raya_auth.json", "r", encoding='utf8') as f:
        CONFIG = json.load(f)
    HOST = CONFIG['host']

def login():
    global TOKEN
    url = f"{HOST}/api/login"
    payload = {"username": CONFIG['username'], "password": CONFIG['password']}
    headers = {"content-type": "application/json"}
    response = requests.post(url, json=payload, headers=headers)
    TOKEN = response.json()["data"]["token"]

def get_status():
    '''获取服务状态'''    
    url = f"{HOST}/api/touch"
    response = requests.get(url, headers={"Authorization": TOKEN})
    return response.json()

def get_outbounds():
    '''获取出站'''    
    url = f"{HOST}/api/outbounds"
    response = requests.get(url, headers={"Authorization": TOKEN})
    return response.json()["data"]["outbounds"]

def main():
    load_config()
    login()
    
    # 获取服务状态
    status = get_status()
    
    # 获取订阅信息和已连接代理
    subscriptions = status["data"]["touch"]["subscriptions"]
    connected_servers = status["data"]["touch"]["connectedServer"]
    
    logging.info("=== 订阅地址信息 ===")
    for sub in subscriptions:
        sub_id = sub["id"]
        address = sub.get("address", "")
        remarks = sub.get("remarks", f"ID: {sub_id}")
        logging.info(f"订阅ID: {sub_id}, 名称: {remarks}, 地址: {address}")
        # 获取订阅内容
        sub_content = get_subscription_content(address)
        proxy_lines = filter_proxy_content(sub_content)
        # 显示该订阅下的已连接代理
        logging.info(f"  已连接代理:")
        for connect in connected_servers:
            if connect.get("sub") == sub_id - 1:  # sub_id 是从1开始，sub 是从0开始
                node_id = connect.get("id")
                # 查找该节点的详细信息
                for server in sub["servers"]:
                    if server["id"] == node_id:
                        node_name = server.get("name", "未知")
                        logging.info(f"    - 节点ID: {node_id}, 节点名称: {node_name}")
                        # 获取订阅内容并获取对应行数的代理配置
                        if proxy_lines and node_id - 1 < len(proxy_lines):
                            proxy_config = proxy_lines[node_id - 1]
                            logging.info(f"    - 代理配置: {proxy_config}")
                        break
    

if __name__ == "__main__":
    main()
