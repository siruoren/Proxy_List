// ==UserScript==
// @name         gfy_exercises
// @namespace    http://tampermonkey.net/
// @version      2026.10.20.1117
// @description  一键复制所有题目、选项及作答判定结果
// @author       You
// @match        https://app.goodfull.vip/v2.0/knowledge/**
// @icon         data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==
// @grant        none
// @updateURL    https://ghfast.top/https://raw.githubusercontent.com/siruoren/Proxy_List/main/gfy_exercises.user.js
// @downloadURL  https://ghfast.top/https://raw.githubusercontent.com/siruoren/Proxy_List/main/gfy_exercises.user.js
// ==/UserScript==

(function() {
    'use strict';

    const BTN_ID = 'gfy-copy-btn';

    // 递归获取元素及其所有子元素的文本
    function getNestedText(element) {
        let text = '';
        for (let node of element.childNodes) {
            if (node.nodeType === Node.TEXT_NODE) {
                text += node.textContent.trim() + ' ';
            } else if (node.nodeType === Node.ELEMENT_NODE) {
                text += getNestedText(node);
            }
        }
        return text.trim();
    }

    // 获取选项框的勾选状态：优先看 aria-checked，其次看 icon 的 --checked 类
    function isChecked(item) {
        if (item.getAttribute('aria-checked') === 'true') return true;
        return !!item.querySelector('.van-radio__icon--checked, .van-checkbox__icon--checked');
    }

    // 按题目块拆分：每道题在独立的 question-content[id^="answer-"] 块里，
    // question-main 只是外层容器（内含全部题目），不能按它拆题。
    // 首次打开（未作答）页面可能没有 answer-N 编号，逐级兜底到任意 question-content
    function getQuestionBlocks() {
        let blocks = [...document.querySelectorAll('.question-content[id^="answer-"]')];
        if (blocks.length === 0) {
            blocks = [...document.querySelectorAll('.question-content')];
        }
        if (blocks.length === 0) {
            blocks = [...document.querySelectorAll('.question-main')];
        }
        return blocks;
    }

    // 获取单个题目的文本：题干 + 选项 + 判定结果（不解析对错答案）
    function getQuestionText(blockEl) {
        // 题干取 question-title；不能用 question-subject（其中嵌有选项和作答结果标签）
        const title = blockEl.querySelector('.question-title') || blockEl.querySelector('.question-subject');
        let text = title ? getNestedText(title) : getNestedText(blockEl);

        // 选项：Vant 的 radio/checkbox 外层元素带 role 属性，找不到时兜底用类名
        let options = blockEl.querySelectorAll('[role="radio"], [role="checkbox"]');
        if (options.length === 0) {
            options = blockEl.querySelectorAll('.van-radio, .van-checkbox');
        }

        const lines = [];
        options.forEach(opt => {
            const label = opt.querySelector('.van-radio__label, .van-checkbox__label') || opt;
            const line = getNestedText(label);
            if (!line) return;
            // ✅ 标记已勾选的选项
            lines.push(`${isChecked(opt) ? '✅ ' : ''}${line}`);
        });
        if (lines.length > 0) text += `\n${lines.join('\n')}`;

        // 判定结果：作答后页面在 ansewr-text 节点显示（类名为站点原样拼写），原样输出全部信息
        const judgeEl = blockEl.querySelector('.ansewr-text');
        const judge = judgeEl ? getNestedText(judgeEl) : '';
        if (judge) text += `\n【判定】${judge}`;
        return text;
    }

    // 获取所有题目文本
    function getAllQuestionsText() {
        const blocks = getQuestionBlocks();
        if (blocks.length === 0) return '';
        return blocks
            .map((el, i) => `【第${i + 1}题】${getQuestionText(el)}`)
            .join('\n\n');
    }

    // 按钮状态提示
    function flashButton(btn, message, color) {
        const original = btn.textContent;
        btn.textContent = message;
        btn.style.backgroundColor = color;
        setTimeout(() => {
            btn.textContent = original;
            btn.style.backgroundColor = '#409eff';
        }, 2000);
    }

    // 复制文本，clipboard 失败时回退到 execCommand
    function copyText(text) {
        return navigator.clipboard.writeText(text).catch(() => {
            const textarea = document.createElement('textarea');
            textarea.value = text;
            document.body.appendChild(textarea);
            textarea.select();
            document.execCommand('copy');
            document.body.removeChild(textarea);
        });
    }

    // 创建一键复制按钮
    function createCopyButton() {
        const btn = document.createElement('button');
        btn.id = BTN_ID;
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
                flashButton(btn, '未找到题目', '#f56c6c');
                return;
            }
            copyText(text).then(() => {
                flashButton(btn, '复制成功！', '#67c23a');
            }).catch(() => {
                flashButton(btn, '复制失败', '#f56c6c');
            });
        });
        return btn;
    }

    function mountButton() {
        if (document.body && !document.getElementById(BTN_ID)) {
            document.body.appendChild(createCopyButton());
        }
    }

    // SPA 页面 DOM 可能被框架重绘，监听 body 子节点变化并重新挂载按钮
    mountButton();
    new MutationObserver(mountButton).observe(document.body, { childList: true });
})();
