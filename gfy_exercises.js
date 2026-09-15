// ==UserScript==
// @name         gfy_exercises
// @namespace    http://tampermonkey.net/
// @version      2026-06-29
// @description  try to take over the world!
// @author       You
// @match        https://app.goodfull.vip/v2.0/knowledge/**
// @icon         data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==
// @grant        none
// ==/UserScript==

(function() {
    'use strict';
// 递归获取元素及其所有子元素的文本
function getNestedText(element) {
    let text = '';

    // 遍历所有子节点
    for (let node of element.childNodes) {
        if (node.nodeType === Node.TEXT_NODE) {
            // 文本节点
            text += node.textContent.trim() + ' ';
        } else if (node.nodeType === Node.ELEMENT_NODE) {
            // 元素节点，递归处理
            text += getNestedText(node);
        }
    }
    return text.trim();
}

// 获取所有题目文本
function getAllQuestionsText() {
    const elements = document.getElementsByClassName('question-main');
    if (elements.length === 0) return '';
    let allText = '';
    for (let i = 0; i < elements.length; i++) {
        const text = getNestedText(elements[i]);
        allText += `【第${i + 1}题】${text}\n\n`;
    }
    return allText.trim();
}

// 创建一键复制按钮
function createCopyButton() {
    const btn = document.createElement('button');
    btn.textContent = '一键复制所有题目';
    Object.assign(btn.style, {
        position: 'fixed',
        top: '10px',
        right: '10px',
        zIndex: '99999',
        padding: '8px 16px',
        backgroundColor: '#409eff',
        color: '#fff',
        border: 'none',
        borderRadius: '4px',
        cursor: 'pointer',
        fontSize: '14px',
        boxShadow: '0 2px 6px rgba(0,0,0,0.3)',
    });
    btn.addEventListener('click', () => {
        const text = getAllQuestionsText();
        if (!text) {
            btn.textContent = '未找到题目';
            btn.style.backgroundColor = '#f56c6c';
            setTimeout(() => {
                btn.textContent = '一键复制所有题目';
                btn.style.backgroundColor = '#409eff';
            }, 2000);
            return;
        }
        navigator.clipboard.writeText(text).then(() => {
            btn.textContent = '复制成功！';
            btn.style.backgroundColor = '#67c23a';
            setTimeout(() => {
                btn.textContent = '一键复制所有题目';
                btn.style.backgroundColor = '#409eff';
            }, 2000);
        }).catch(() => {
            // fallback
            const textarea = document.createElement('textarea');
            textarea.value = text;
            document.body.appendChild(textarea);
            textarea.select();
            document.execCommand('copy');
            document.body.removeChild(textarea);
            btn.textContent = '复制成功！';
            btn.style.backgroundColor = '#67c23a';
            setTimeout(() => {
                btn.textContent = '一键复制所有题目';
                btn.style.backgroundColor = '#409eff';
            }, 2000);
        });
    });
    document.body.appendChild(btn);
}

createCopyButton();


})();