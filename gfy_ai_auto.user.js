// ==UserScript==
// @name         gfy_ai_auto
// @namespace    http://tampermonkey.net/
// @version      2026.10.20.5
// @description  接入豆包自动答题：收集题目→豆包作答→自动勾选；不检测登录状态，未登录时持续重试，登录后自动继续
// @author       You
// @match        https://app.goodfull.vip/v2.0/knowledge/**
// @match        https://www.doubao.com/*
// @icon         data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_addValueChangeListener
// @run-at       document-idle
// @updateURL    https://ghfast.top/https://raw.githubusercontent.com/siruoren/Proxy_List/main/gfy_ai_auto.user.js
// @downloadURL  https://ghfast.top/https://raw.githubusercontent.com/siruoren/Proxy_List/main/gfy_ai_auto.user.js
// ==/UserScript==

(function () {
    'use strict';

    // ===================== 常量与跨标签页存储键 =====================
    const EXAM = location.host.indexOf('goodfull') !== -1;
    const DOUBAO = location.host.indexOf('doubao.com') !== -1;

    const KEY_REQ = 'gfy_ai_request';      // 题目页 -> 豆包页：题目数据
    const KEY_ANS = 'gfy_ai_answers';      // 豆包页 -> 题目页：答案与进度
    const KEY_STATUS = 'gfy_ai_status';    // 豆包页 -> 题目页：登录/就绪状态
    const KEY_SESSION = 'gfy_ai_session';  // 豆包页登录成功后抓取并本地保存的会话信息

    const DOUBAO_URL = 'https://www.doubao.com/chat/';
    const CHUNK_SIZE = 8;                  // 每次发送给豆包的题目数量
    const REPLY_TIMEOUT = 150000;          // 等待豆包回复超时（毫秒）

    // 豆包页面选择器（站点改版时可在此调整）
    const DOUBAO_SEL = {
        input: ['textarea[data-testid="chat_input_input"]', 'textarea'],
        send: ['button[data-testid="chat_input_send_button"]', 'button[class*="send"]'],
        stop: ['button[data-testid="chat_input_stop_button"]'],
        reply: ['[data-testid="receive_message"]', '[data-testid="message_message_content"]', '.markdown-body'],
    };

    // ===================== 通用工具 =====================
    function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

    function qsel(selectors) {
        for (const s of selectors) {
            const el = document.querySelector(s);
            if (el) return el;
        }
        return null;
    }

    function qselAll(selectors) {
        for (const s of selectors) {
            const els = [...document.querySelectorAll(s)];
            if (els.length) return els;
        }
        return [];
    }

    // 递归获取元素文本（与 gfy_exercises 同源逻辑）
    function getNestedText(el) {
        if (!el) return '';
        const parts = [];
        (function walk(node) {
            node.childNodes.forEach(c => {
                if (c.nodeType === Node.TEXT_NODE) {
                    const t = c.textContent.replace(/\s+/g, ' ');
                    if (t.trim()) parts.push(t);
                } else if (c.nodeType === Node.ELEMENT_NODE) {
                    walk(c);
                }
            });
        })(el);
        return parts.join('').trim();
    }

    // 获取选项框的勾选状态：优先看 aria-checked，其次看 icon 的 --checked 类
    function isChecked(item) {
        if (item.getAttribute('aria-checked') === 'true') return true;
        return !!item.querySelector('.van-radio__icon--checked, .van-checkbox__icon--checked');
    }

    function safeParse(str, fallback) {
        try { return JSON.parse(str); } catch (_) { return fallback; }
    }

    // ===================== 题目页逻辑 =====================
    if (EXAM) {
        let currentReqId = null;
        let running = false;
        let aiBtn = null;

        // 按题目块拆分：每道题在独立的 question-content[id^="answer-"] 块里
        function getQuestionBlocks() {
            let blocks = [...document.querySelectorAll('.question-content[id^="answer-"]')];
            if (!blocks.length) blocks = [...document.querySelectorAll('.question-content')];
            return blocks;
        }

        // 解析全部题目：题号、题型、题干、选项（保留 DOM 引用用于自动点击）
        function parseQuestions() {
            const blocks = getQuestionBlocks();
            return blocks.map((b, i) => {
                const titleEl = b.querySelector('.question-title') || b.querySelector('.question-subject');
                const title = titleEl ? getNestedText(titleEl) : getNestedText(b);
                const m = title.match(/(\d+)\s*(单选题|多选题|判断题)/);
                const n = m ? m[1] : String(i + 1);
                const type = m ? m[2] : '单选题';
                let opts = [...b.querySelectorAll('[role="radio"], [role="checkbox"]')];
                if (!opts.length) opts = [...b.querySelectorAll('.van-radio, .van-checkbox')];
                const options = opts.map(o => {
                    const label = o.querySelector('.van-radio__label, .van-checkbox__label') || o;
                    const t = getNestedText(label);
                    const km = t.match(/^([A-Za-z]+)\s*[、.．,，:：]/);
                    return { k: km ? km[1].toUpperCase() : '', t, el: o };
                });
                return { n, type, title, options };
            });
        }

        // 点击选项（Vant 组件监听在根元素上，200ms 后复查，未生效时点击内部 input 兜底）
        function clickOption(el) {
            el.click();
            setTimeout(() => {
                if (!isChecked(el)) {
                    const input = el.querySelector('input');
                    if (input) input.click(); else el.click();
                }
            }, 200);
        }

        // 应用豆包返回的答案：逐题匹配并勾选
        function applyAnswers(data) {
            if (!data || data.reqId !== currentReqId || running === false) return;
            const qs = window.__gfyQs || [];
            const byN = {};
            qs.forEach(q => { byN[q.n] = q; });
            const answers = data.answers || {};
            Object.keys(answers).forEach(n => {
                const q = byN[n];
                if (!q) return;
                (answers[n] || []).forEach(k => {
                    const key = String(k).trim().toUpperCase();
                    q.options.forEach(o => {
                        const hit = (o.k && o.k === key)
                            || o.t.toUpperCase().indexOf(key) !== -1
                            || key.indexOf(o.t) !== -1;
                        if (hit && !isChecked(o.el)) clickOption(o.el);
                    });
                });
            });
            const done = Object.keys(answers).length;
            if (done >= (data.total || qs.length)) {
                aiBtn.textContent = `完成 ${done}/${data.total}，已自动选择`;
                running = false; // 允许再次点击重新运行
            } else {
                aiBtn.textContent = `AI 答题中 ${done}/${data.total}`;
            }
        }

        function showToast(text) {
            const d = document.createElement('div');
            d.textContent = text;
            d.style.cssText = 'position:fixed;top:60px;left:50%;transform:translateX(-50%);z-index:999999;'
                + 'background:#e8f5e9;color:#1b5e20;border:1px solid #81c784;border-radius:8px;'
                + 'padding:10px 16px;font-size:14px;box-shadow:0 4px 12px rgba(0,0,0,.15);';
            document.body.appendChild(d);
            setTimeout(() => d.remove(), 4000);
        }

        function mountButton() {
            aiBtn = document.createElement('button');
            aiBtn.id = 'gfy-ai-btn';
            aiBtn.textContent = 'AI 自动答题';
            aiBtn.style.cssText = 'position:fixed;right:20px;bottom:70px;z-index:999999;'
                + 'padding:10px 18px;background:#1976d2;color:#fff;border:none;border-radius:8px;'
                + 'font-size:14px;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,.2);';
            aiBtn.addEventListener('click', onAiClick);
            document.body.appendChild(aiBtn);

            // 监听豆包页回传的答案与会话（状态改由下方轮询持续跟踪，避免事件丢失）
            GM_addValueChangeListener(KEY_ANS, (k, o, nv, remote) => {
                if (!remote || !nv) return;
                applyAnswers(safeParse(nv, null));
            });
            // 豆包标签页登录成功 -> 自动捕获新会话：本页不刷新，仅提示并继续
            GM_addValueChangeListener(KEY_SESSION, (k, o, nv, remote) => {
                if (!remote || !nv) return;
                const s = safeParse(nv, null);
                if (!s) return;
                showToast(`已获取豆包会话并保存（${new Date(s.ts).toLocaleTimeString()}），自动继续答题`);
                aiBtn.textContent = '豆包会话已就绪';
            });

            // 持续跟踪豆包标签页状态：每 1.5s 轮询存储（心跳 + 答案）。
            // 不检测登录状态：未登录时豆包页持续重试，登录后自动继续
            setInterval(() => {
                if (!running) return;
                const st = safeParse(GM_getValue(KEY_STATUS, ''), null);
                const ans = safeParse(GM_getValue(KEY_ANS, ''), null);
                if (ans && ans.reqId === currentReqId) applyAnswers(ans);
                const fresh = st && Date.now() - (st.ts || 0) < 10000;
                if (!fresh) {
                    aiBtn.textContent = '未检测到豆包页面，请确认弹窗未被拦截';
                    return;
                }
                const hasAns = ans && ans.reqId === currentReqId
                    && Object.keys(ans.answers || {}).length > 0;
                if (!hasAns) aiBtn.textContent = '豆包页面已就绪，正在发送题目…';
            }, 1500);
        }

        function onAiClick() {
            const qs = parseQuestions();
            if (!qs.length) { alert('未找到题目，请确认已进入答题页面'); return; }
            const msg = running
                ? '当前任务进行中，将新建豆包标签页重新开始答题，继续？'
                : `已解析 ${qs.length} 道题，将打开豆包页面自动作答并勾选，继续？`;
            if (!confirm(msg)) return;
            running = true;
            window.__gfyQs = qs;
            currentReqId = Date.now();
            const plain = qs.map(q => { const { el, ...rest } = q; return rest; });
            GM_setValue(KEY_REQ, JSON.stringify({ reqId: currentReqId, questions: plain, claimed: null }));
            GM_setValue(KEY_ANS, JSON.stringify({ reqId: currentReqId, answers: {}, progress: 0, total: qs.length }));
            aiBtn.textContent = '等待豆包页面…';
            // 唯一窗口名：豆包标签页卡住或被手动关闭后，再次点击按钮即可强制新开一个答题标签页
            window.open(DOUBAO_URL, 'gfy_doubao_tab_' + currentReqId);
        }

        function init() {
            const mo = new MutationObserver(() => {
                if (!document.getElementById('gfy-ai-btn')) mountButton();
            });
            mo.observe(document.documentElement, { childList: true, subtree: true });
            mountButton();
            // 已有保存的豆包会话时，在按钮上提示保存时间（悬停可见）
            const saved = safeParse(GM_getValue(KEY_SESSION, ''), null);
            if (saved && saved.ts) {
                aiBtn.title = `已保存豆包会话：${new Date(saved.ts).toLocaleString()}`;
            }
        }
        init();
    }

    // ===================== 豆包页逻辑 =====================
    if (DOUBAO) {
        let lastReqId = null;
        let busy = false;
        let banner = null;
        const TAB_TOKEN = Math.random().toString(36).slice(2); // 本标签页认领标记

        function setStatus(reqId, state) {
            // 每次写入都带心跳时间戳，题目页据此判断豆包标签页是否存活
            GM_setValue(KEY_STATUS, JSON.stringify({ reqId, state, ts: Date.now() }));
        }

        // 心跳：独立于答题流程持续写入，答题中也不会中断。
        // 不检测登录状态，始终上报就绪，由答题流程自行重试
        setInterval(() => {
            const req = safeParse(GM_getValue(KEY_REQ, ''), null);
            setStatus(req ? req.reqId : 0, 'ready');
        }, 2000);

        function showBanner(text) {
            if (!banner) {
                banner = document.createElement('div');
                banner.style.cssText = 'position:fixed;top:16px;left:50%;transform:translateX(-50%);z-index:999999;'
                    + 'background:#e3f2fd;color:#0d47a1;border:1px solid #64b5f6;border-radius:8px;'
                    + 'padding:10px 16px;font-size:14px;box-shadow:0 4px 12px rgba(0,0,0,.15);';
                document.body.appendChild(banner);
            }
            banner.textContent = text;
        }

        function findInput() { return qsel(DOUBAO_SEL.input); }
        function findSend() { return qsel(DOUBAO_SEL.send); }
        function findReplies() { return qselAll(DOUBAO_SEL.reply); }

        // 填充输入框：textarea 用原生 setter 触发框架响应，contenteditable 用 execCommand
        function fillInput(ta, text) {
            ta.focus();
            if (ta.tagName === 'TEXTAREA') {
                const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
                setter.call(ta, text);
            } else {
                document.execCommand('insertText', false, text);
            }
            ta.dispatchEvent(new Event('input', { bubbles: true }));
        }

        function clickSend(ta) {
            const btn = findSend();
            if (btn && !btn.disabled) { btn.click(); return; }
            ta.dispatchEvent(new KeyboardEvent('keydown', {
                key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true,
            }));
        }

        // 组装一批评测提示词
        function buildPrompt(chunk, reqId, idx) {
            const body = chunk.map(q => `${q.n}. [${q.type}] ${q.title}\n${q.options.map(o => o.t).join('\n')}`).join('\n\n');
            return `你是考试答题助手。请独立回答以下 ${chunk.length} 道题，忽略之前所有对话内容。`
                + `要求：只输出一个 JSON 对象，格式为 {"answers":{"题号":["选项字母"]}}；`
                + `多选题的数组包含所有正确选项字母，单选题和判断题的数组只包含一个字母。不要输出任何其他文字。\n\n`
                + `${body}\n\n【gfy-${reqId}-${idx}】`;
        }

        // 等待豆包回复完成：新回复出现且文本连续 2 次轮询不变、且不在流式输出中
        async function waitReply(mark, countBefore) {
            const start = Date.now();
            let prev = '';
            let stable = 0;
            while (Date.now() - start < REPLY_TIMEOUT) {
                await sleep(1200);
                const streaming = !!qsel(DOUBAO_SEL.stop);
                const nodes = findReplies().filter(n => n.innerText.indexOf(mark) === -1);
                const newNodes = nodes.slice(countBefore);
                const txt = newNodes.map(n => n.innerText).join('\n').trim();
                if (txt && txt === prev && !streaming) {
                    stable++;
                    if (stable >= 2) return txt;
                } else {
                    stable = 0;
                    prev = txt;
                }
            }
            throw new Error('豆包回复超时');
        }

        // 从回复文本中提取 {"answers": {...}}
        function extractAnswers(text) {
            const m = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
            const candidates = [m && m[1], text].filter(Boolean);
            for (const s of candidates) {
                const b = s.indexOf('{');
                const e = s.lastIndexOf('}');
                if (b === -1 || e <= b) continue;
                const j = safeParse(s.slice(b, e + 1), null);
                if (j && j.answers) return j.answers;
            }
            return null;
        }

        // 发送一批题目并等待答案
        async function answerChunk(reqId, chunk, idx, accumulated) {
            const ta = findInput();
            if (!ta) throw new Error('未找到豆包输入框（可能未登录或页面未加载完成），将持续重试');
            const mark = `【gfy-${reqId}-${idx}】`;
            const countBefore = findReplies().length;
            fillInput(ta, buildPrompt(chunk, reqId, idx));
            await sleep(300);
            clickSend(ta);
            const reply = await waitReply(mark, countBefore);
            const ans = extractAnswers(reply);
            if (!ans) throw new Error('无法从豆包回复中解析答案');
            Object.keys(ans).forEach(n => {
                const v = ans[n];
                accumulated[String(parseInt(n, 10) || n)] = (Array.isArray(v) ? v : [v]).map(x => String(x).trim());
            });
        }

        // 处理新请求：分批发送，逐批合并答案并回传；
        // 通过 claimed 标记认领，多个豆包标签页打开时只有一个作答
        async function processRequest() {
            const req = safeParse(GM_getValue(KEY_REQ, ''), null);
            if (!req || !req.questions || req.reqId === lastReqId) return;
            if (req.claimed && req.claimed !== TAB_TOKEN) return; // 已被其他标签页认领
            busy = true;
            try {
                if (!req.claimed) {
                    req.claimed = TAB_TOKEN;
                    GM_setValue(KEY_REQ, JSON.stringify(req));
                }
                lastReqId = req.reqId;
                const accumulated = {};
                const chunks = [];
                for (let i = 0; i < req.questions.length; i += CHUNK_SIZE) {
                    chunks.push(req.questions.slice(i, i + CHUNK_SIZE));
                }
                for (let i = 0; i < chunks.length; i++) {
                    showBanner(`自动答题中：第 ${i + 1}/${chunks.length} 批…`);
                    await answerChunk(req.reqId, chunks[i], i, accumulated);
                    GM_setValue(KEY_ANS, JSON.stringify({
                        reqId: req.reqId,
                        answers: accumulated,
                        progress: Math.min((i + 1) * CHUNK_SIZE, req.questions.length),
                        total: req.questions.length,
                    }));
                }
                showBanner(`自动答题完成，共 ${req.questions.length} 题，已回传`);
            } catch (e) {
                showBanner(`自动答题出错：${e.message}`);
                // 释放认领，允许本标签页或其他标签页重试
                const cur = safeParse(GM_getValue(KEY_REQ, ''), null);
                if (cur && cur.reqId === req.reqId) {
                    cur.claimed = null;
                    GM_setValue(KEY_REQ, JSON.stringify(cur));
                }
                lastReqId = null;
            }
            busy = false;
        }

        // 登录成功后抓取当前会话（可访问的 Cookie + 时间戳）并保存到本地，
        // 内容变化时才写入，避免循环内重复写值
        function captureSession(reqId) {
            const cookies = document.cookie;
            const stored = safeParse(GM_getValue(KEY_SESSION, ''), null);
            if (stored && stored.cookies === cookies) return stored;
            const session = { reqId, cookies, ts: Date.now(), url: location.origin };
            GM_setValue(KEY_SESSION, JSON.stringify(session));
            return session;
        }

        // 主循环：不检测登录状态，持续认领处理请求；未登录时发送失败会不断重试，
        // 登录成功后自动继续。会话在输入框可用时抓取保存
        async function boot() {
            for (;;) {
                const req = safeParse(GM_getValue(KEY_REQ, ''), null);
                if (req && !busy) {
                    await processRequest();
                } else if (!req) {
                    if (findInput()) {
                        captureSession(0);
                        showBanner('已登录：豆包会话已保存。脚本待命：请在题目页面点击「AI 自动答题」');
                    } else {
                        showBanner('脚本待命：等待题目页面任务（未登录也可答题，登录后效果更佳）');
                    }
                } else if (!busy) {
                    showBanner('已登录：豆包会话已保存。脚本待命：等待新任务');
                }
                await sleep(2000);
            }
        }
        boot();
    }
})();
