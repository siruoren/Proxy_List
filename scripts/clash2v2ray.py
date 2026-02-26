#!/usr/bin/env python3
"""
Clash配置文件转V2Ray链接工具
支持转换vmess、ss、trojan协议
"""

import yaml
import base64
import json
import sys
from urllib.parse import quote, urlencode

class ClashToV2ray:
    def __init__(self, input_file, output_file):
        self.input_file = input_file
        self.output_file = output_file
        self.proxies = []
    
    def load_yaml(self):
        """加载YAML配置文件"""
        try:
            with open(self.input_file, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f)
                if 'proxies' in config:
                    self.proxies = config['proxies']
                else:
                    raise ValueError("未找到 'proxies' 节点")
            print(f"成功加载配置文件，找到 {len(self.proxies)} 个节点")
        except Exception as e:
            print(f"加载配置文件失败: {e}")
            raise
    
    def generate_vmess_link(self, proxy):
        """生成vmess链接"""
        vmess_config = {
            "v": "2",
            "ps": proxy.get('name', 'Unknown'),
            "add": proxy['server'],
            "port": str(proxy['port']),
            "id": proxy['uuid'],
            "aid": str(proxy.get('alterId', 0)),
            "net": proxy.get('network', 'tcp'),
            "type": proxy.get('type', 'none'),
            "host": proxy.get('ws-headers', {}).get('Host', ''),
            "path": proxy.get('ws-path', ''),
            "tls": "tls" if proxy.get('tls', False) else ""
        }
        json_str = json.dumps(vmess_config)
        return f"vmess://{base64.b64encode(json_str.encode()).decode()}"
    
    def generate_ss_link(self, proxy):
        """生成ss链接"""
        # ss://method:password@server:port#name
        method = proxy['cipher']
        password = proxy['password']
        server = proxy['server']
        port = proxy['port']
        name = proxy.get('name', 'Unknown')
        
        # 构建ss链接
        ss_part = f"{method}:{password}@{server}:{port}"
        ss_encoded = base64.b64encode(ss_part.encode()).decode()
        name_encoded = quote(name)
        return f"ss://{ss_encoded}#{name_encoded}"
    
    def generate_trojan_link(self, proxy):
        """生成trojan链接"""
        # trojan://password@server:port#name
        password = proxy['password']
        server = proxy['server']
        port = proxy['port']
        name = proxy.get('name', 'Unknown')
        
        # 构建trojan链接
        trojan_part = f"{password}@{server}:{port}"
        name_encoded = quote(name)
        return f"trojan://{trojan_part}#{name_encoded}"
    
    def convert(self):
        """转换所有支持的协议"""
        links = []
        protocol_count = {
            'vmess': 0,
            'ss': 0,
            'trojan': 0,
            'unknown': 0
        }
        
        for proxy in self.proxies:
            proxy_type = proxy.get('type', 'unknown')
            
            try:
                if proxy_type == 'vmess':
                    links.append(self.generate_vmess_link(proxy))
                    protocol_count['vmess'] += 1
                elif proxy_type == 'ss':
                    links.append(self.generate_ss_link(proxy))
                    protocol_count['ss'] += 1
                elif proxy_type == 'trojan':
                    links.append(self.generate_trojan_link(proxy))
                    protocol_count['trojan'] += 1
                else:
                    protocol_count['unknown'] += 1
            except Exception as e:
                print(f"转换节点 {proxy.get('name', 'Unknown')} 失败: {e}")
        
        print(f"转换完成，成功转换 {len(links)} 个节点")
        print(f"协议分布: vmess={protocol_count['vmess']}, ss={protocol_count['ss']}, trojan={protocol_count['trojan']}, unknown={protocol_count['unknown']}")
        return links
    
    def save_links(self, links):
        """保存链接到文件"""
        try:
            with open(self.output_file, 'w', encoding='utf-8') as f:
                f.write('\n'.join(links))
            print(f"结果已保存至 {self.output_file}")
        except Exception as e:
            print(f"保存文件失败: {e}")
            raise

def main():
    """主函数"""
    if len(sys.argv) != 3:
        print("用法: python clash2v2ray.py <input_file> <output_file>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        converter = ClashToV2ray(input_file, output_file)
        converter.load_yaml()
        links = converter.convert()
        converter.save_links(links)
    except Exception as e:
        print(f"执行失败: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
