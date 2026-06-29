import json
import logging
import secrets
import socket
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from app.characters import list_characters
from app.config import get_settings
from app.main import build_orchestrator


STATIC_DIR = Path(__file__).resolve().parent / "static"


HTML = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>小动物夜谈会 · 心理陪伴 Agent</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #fff0f2;
      --panel: rgba(255, 252, 247, 0.88);
      --user: #dcefff;
      --deer: #fffdf8;
      --text: #3d2d27;
      --muted: #91786b;
      --accent: #d99074;
      --accent-dark: #9f604b;
      --border: rgba(226, 190, 166, 0.72);
      --soft-pink: #ffe3e3;
      --soft-green: #e5f2df;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background:
        linear-gradient(rgba(255, 239, 244, 0.1), rgba(255, 233, 231, 0.18)),
        url("/static/night-forest-bg-warm.png") center center / cover no-repeat fixed,
        linear-gradient(180deg, #2c294f 0%, #ffe1dd 100%);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      min-height: 100vh;
      overflow: hidden;
    }
    body::before,
    body::after {
      content: "";
      position: fixed;
      inset: 0;
      pointer-events: none;
    }
    body::before {
      z-index: 0;
      background: radial-gradient(circle at 50% 28%, rgba(255, 248, 235, 0.18), transparent 42%);
    }
    body::after {
      display: none;
    }
    .app {
      position: relative;
      z-index: 1;
      width: min(1280px, 100vw);
      height: 100vh;
      margin: 0 auto;
      display: grid;
      grid-template-columns: 210px minmax(0, 1fr) 230px;
      grid-template-rows: auto 1fr auto;
      padding: 12px 14px;
      gap: 10px;
    }
    .top-bar {
      grid-column: 1 / -1;
      grid-row: 1;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 14px;
      min-height: 56px;
      padding: 10px 16px;
      border: 1px solid rgba(255, 234, 221, 0.5);
      border-radius: 24px;
      background:
        linear-gradient(135deg, rgba(46, 43, 82, 0.74), rgba(126, 91, 121, 0.55)),
        radial-gradient(circle at 18% 20%, rgba(255, 238, 185, 0.35), transparent 28%);
      color: #fffaf3;
      box-shadow: 0 16px 36px rgba(50, 32, 62, 0.16);
      backdrop-filter: blur(14px);
    }
    .app-title {
      display: flex;
      align-items: center;
      gap: 10px;
      min-width: 0;
    }
    .app-title-mark {
      display: grid;
      place-items: center;
      width: 36px;
      height: 36px;
      border-radius: 14px;
      background: rgba(255, 246, 221, 0.18);
      border: 1px solid rgba(255, 248, 232, 0.28);
      box-shadow: inset 0 0 18px rgba(255, 244, 207, 0.18);
    }
    .app-title-text {
      min-width: 0;
    }
    .app-title-name {
      font-weight: 800;
      font-size: 18px;
      letter-spacing: 0.06em;
    }
    .app-title-subtitle {
      margin-top: 2px;
      color: rgba(255, 250, 243, 0.72);
      font-size: 12px;
    }
    .app-scene-note {
      color: rgba(255, 250, 243, 0.78);
      font-size: 12px;
      white-space: nowrap;
    }
    .control-panel,
    .animal-panel {
      background: rgba(255, 252, 246, 0.88);
      border: 1px solid var(--border);
      border-radius: 24px;
      padding: 10px 12px;
      box-shadow: 0 12px 30px rgba(155, 101, 75, 0.1);
      backdrop-filter: blur(14px);
      min-height: 0;
      overflow-y: auto;
    }
    .control-panel {
      grid-column: 1;
      grid-row: 2 / -1;
    }
    .animal-panel {
      grid-column: 3;
      grid-row: 2 / -1;
    }
    .brand {
      display: flex;
      gap: 10px;
      align-items: center;
    }
    .panel-heading {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
    }
    .panel-heading h1 {
      font-size: 18px;
    }
    .panel-dot {
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: #9bc684;
      box-shadow: 0 0 0 4px rgba(155, 198, 132, 0.2);
    }
    .deer-logo {
      width: 44px;
      height: 44px;
      object-fit: cover;
      border-radius: 17px;
      background: #fff;
      border: 2px solid rgba(255, 255, 255, 0.86);
      box-shadow: 0 10px 24px rgba(147, 91, 65, 0.16);
    }
    h1 { margin: 0; font-size: 20px; letter-spacing: 0.02em; }
    .subtitle { margin-top: 3px; color: var(--muted); font-size: 12px; }
    .brand .subtitle {
      display: none;
    }
    nav {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
      margin-top: 8px;
    }
    .character-strip {
      display: none;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
      margin-top: 8px;
    }
    .group-toggle {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      width: 100%;
      margin-bottom: 10px;
      padding: 9px 10px;
      border-radius: 18px;
      background: rgba(255, 248, 239, 0.78);
      color: #6f4a3e;
      border: 1px solid rgba(226, 190, 166, 0.56);
      text-align: left;
    }
    .group-toggle.active {
      background: linear-gradient(135deg, #fff0d6, #ffe0de);
      box-shadow: 0 8px 18px rgba(147, 91, 65, 0.1);
    }
    .toggle-label {
      font-size: 13px;
      font-weight: 700;
    }
    .toggle-note {
      color: var(--muted);
      font-size: 11px;
      line-height: 1.35;
    }
    .toggle-pill {
      flex: 0 0 auto;
      padding: 4px 8px;
      border-radius: 999px;
      background: rgba(242, 222, 207, 0.9);
      color: #69483a;
      font-size: 12px;
    }
    .group-toggle.active .toggle-pill {
      background: var(--accent);
      color: #fff;
    }
    .quick-title {
      margin-top: 12px;
      color: #5f3d26;
      font-size: 13px;
      font-weight: 800;
    }
    .sidebar-section-title {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-top: 14px;
      color: #5f3d26;
      font-size: 13px;
      font-weight: 800;
    }
    .sidebar-section-title::after {
      content: "";
      height: 1px;
      flex: 1;
      background: rgba(226, 190, 166, 0.58);
    }
    .cozy-list {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
      margin-top: 8px;
    }
    .cozy-card {
      border: 1px solid rgba(226, 190, 166, 0.6);
      border-radius: 18px;
      padding: 10px;
      background: rgba(255, 248, 239, 0.76);
      color: #6f4a3e;
      text-align: center;
      box-shadow: 0 8px 18px rgba(120, 80, 50, 0.06);
    }
    .cozy-card.clickable {
      cursor: pointer;
    }
    .cozy-card.clickable:hover {
      background: rgba(255, 238, 224, 0.9);
    }
    .selected-animal-card {
      margin-top: 12px;
      border: 1px solid rgba(226, 190, 166, 0.68);
      border-radius: 22px;
      padding: 12px;
      background: rgba(255, 250, 243, 0.82);
      box-shadow: 0 10px 24px rgba(120, 80, 50, 0.08);
    }
    .selected-animal-top {
      display: grid;
      grid-template-columns: 64px 1fr;
      gap: 10px;
      align-items: center;
    }
    .selected-animal-avatar {
      width: 64px;
      height: 76px;
      border-radius: 18px;
      object-fit: contain;
      background: transparent;
      border: 0;
      box-shadow: 0 8px 18px rgba(140, 92, 72, 0.13);
    }
    .selected-animal-name {
      font-size: 14px;
      font-weight: 800;
      color: #5f3d26;
    }
    .selected-animal-mood {
      margin-top: 3px;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.35;
    }
    .selected-animal-intro {
      margin-top: 9px;
      color: #6f4a3e;
      font-size: 12px;
      line-height: 1.55;
    }
    .settings-list {
      display: grid;
      gap: 7px;
      margin-top: 8px;
    }
    .settings-item {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      width: 100%;
      padding: 9px 10px;
      border-radius: 16px;
      background: rgba(255, 248, 239, 0.7);
      color: #6f4a3e;
      border: 1px solid rgba(226, 190, 166, 0.48);
      text-align: left;
      font-size: 12px;
    }
    .settings-arrow {
      color: rgba(145, 120, 107, 0.82);
    }
    .dev-panel {
      position: fixed;
      right: 18px;
      top: 88px;
      width: min(520px, calc(100vw - 36px));
      max-height: calc(100vh - 112px);
      overflow-y: auto;
      z-index: 20;
      background: rgba(255, 250, 243, 0.96);
      border: 1px solid var(--border);
      border-radius: 22px;
      padding: 14px;
      box-shadow: 0 18px 46px rgba(70, 45, 20, 0.2);
      backdrop-filter: blur(14px);
    }
    .dev-panel-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      margin-bottom: 10px;
    }
    .dev-panel h2 {
      margin: 0;
      font-size: 16px;
      color: #5f3d26;
    }
    .dev-section {
      border-top: 1px dashed rgba(226, 190, 166, 0.7);
      padding-top: 10px;
      margin-top: 10px;
    }
    .dev-section h3 {
      margin: 0 0 7px;
      font-size: 13px;
      color: #5f3d26;
    }
    .dev-list {
      display: grid;
      gap: 7px;
    }
    .dev-item {
      border-radius: 14px;
      padding: 8px;
      background: rgba(255, 248, 239, 0.78);
      border: 1px solid rgba(226, 190, 166, 0.42);
    }
    .dev-plan-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 7px;
    }
    .dev-plan-cell {
      border-radius: 12px;
      padding: 8px;
      background: rgba(255, 255, 255, 0.5);
      border: 1px solid rgba(226, 190, 166, 0.36);
    }
    .dev-plan-label {
      margin-bottom: 3px;
      color: rgba(111, 74, 62, 0.72);
      font-size: 11px;
    }
    .dev-plan-value {
      color: #4b3829;
      font-size: 12px;
      line-height: 1.45;
    }
    .dev-tags {
      display: flex;
      flex-wrap: wrap;
      gap: 5px;
    }
    .dev-tag {
      border-radius: 999px;
      padding: 3px 7px;
      background: rgba(255, 248, 239, 0.9);
      border: 1px solid rgba(226, 190, 166, 0.45);
      color: #6f4a3e;
      font-size: 11px;
    }
    .dev-pre {
      margin: 7px 0 0;
      max-height: 220px;
      overflow: auto;
      white-space: pre-wrap;
      word-break: break-word;
      font: 11px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      color: #4b3829;
      background: rgba(255, 255, 255, 0.58);
      border-radius: 12px;
      padding: 8px;
    }
    .cozy-title {
      font-size: 12px;
      font-weight: 700;
      margin-bottom: 3px;
    }
    .cozy-text {
      color: var(--muted);
      font-size: 11px;
      line-height: 1.45;
    }
    .character-button {
      display: grid;
      grid-template-columns: auto;
      justify-items: center;
      gap: 4px;
      min-width: 0;
      padding: 6px 4px;
      border-radius: 16px;
      background: rgba(255, 248, 239, 0.78);
      color: #6f4a3e;
      border: 1px solid rgba(226, 190, 166, 0.72);
      text-align: center;
    }
    .character-button.active {
      background: linear-gradient(135deg, #fff0d6, #ffe0de);
      color: #5a352a;
      box-shadow: 0 8px 20px rgba(147, 91, 65, 0.13);
    }
    .character-strip.auto-mode .character-button {
      opacity: 0.82;
    }
    .character-avatar {
      width: 36px;
      height: 36px;
      border-radius: 14px;
      object-fit: cover;
      background: #fff;
      border: 1px solid rgba(255, 255, 255, 0.9);
    }
    .character-name {
      font-size: 12px;
      font-weight: 700;
      line-height: 1.2;
    }
    .character-voice {
      display: none;
    }
    .tab {
      background: rgba(255, 232, 219, 0.92);
      color: #6f4a3e;
      padding: 8px 12px;
      border-radius: 999px;
    }
    .tab.active {
      background: var(--accent);
      color: #fff;
    }
    .view { min-height: 0; overflow: hidden; }
    .hidden { display: none !important; }
    #messages {
      grid-column: 2;
      grid-row: 2;
      overflow-y: auto;
      background: rgba(255, 252, 246, 0.64);
      border: 1px solid var(--border);
      border-radius: 22px;
      padding: 14px;
      backdrop-filter: blur(10px);
    }
    .row { display: flex; margin: 9px 0; }
    .row.user { justify-content: flex-end; }
    .row.deer {
      justify-content: flex-start;
      align-items: flex-start;
      gap: 10px;
    }
    .avatar {
      width: 40px;
      height: 40px;
      border-radius: 16px;
      object-fit: cover;
      background: #fff;
      border: 2px solid rgba(255, 255, 255, 0.9);
      box-shadow: 0 8px 18px rgba(140, 92, 72, 0.13);
      flex: 0 0 auto;
    }
    .emoji-avatar {
      display: grid;
      place-items: center;
      font-size: 24px;
    }
    .avatar-wrap {
      position: relative;
      flex: 0 0 auto;
    }
    .avatar-action {
      position: absolute;
      right: -4px;
      top: -5px;
      width: 20px;
      height: 20px;
      display: grid;
      place-items: center;
      border-radius: 999px;
      background: rgba(255, 252, 246, 0.96);
      border: 1px solid rgba(226, 190, 166, 0.7);
      box-shadow: 0 6px 14px rgba(94, 57, 37, 0.12);
      font-size: 12px;
      animation: actionPulse 1.8s ease-in-out infinite;
    }
    .avatar-wrap[data-action="tilt_head"] .avatar {
      animation: tiltHead 2.4s ease-in-out infinite;
      transform-origin: 50% 70%;
    }
    .avatar-wrap[data-action="soft_lean"] .avatar {
      animation: softLean 2.6s ease-in-out infinite;
    }
    .avatar-wrap[data-action="slow_nod"] .avatar {
      animation: slowNod 2.8s ease-in-out infinite;
    }
    .avatar-wrap[data-action="warm_glow"] .avatar {
      box-shadow: 0 0 0 4px rgba(255, 225, 150, 0.25), 0 10px 22px rgba(140, 92, 72, 0.13);
    }
    @keyframes tiltHead {
      0%, 100% { transform: rotate(0deg); }
      45%, 70% { transform: rotate(-8deg); }
    }
    @keyframes softLean {
      0%, 100% { transform: translateX(0); }
      48%, 72% { transform: translateX(3px); }
    }
    @keyframes slowNod {
      0%, 100% { transform: translateY(0); }
      45%, 70% { transform: translateY(2px); }
    }
    @keyframes actionPulse {
      0%, 100% { transform: scale(1); opacity: 0.82; }
      50% { transform: scale(1.08); opacity: 1; }
    }
    .bubble {
      max-width: min(680px, 86%);
      padding: 10px 13px;
      border-radius: 19px;
      line-height: 1.55;
      white-space: pre-wrap;
      box-shadow: 0 8px 22px rgba(94, 57, 37, 0.07);
    }
    .message-head {
      display: flex;
      align-items: center;
      gap: 6px;
      margin-bottom: 4px;
    }
    .message-face {
      font-size: 15px;
      line-height: 1;
    }
    .message-body {
      overflow: hidden;
      transition: max-height 0.15s ease;
    }
    .message-body.collapsed {
      max-height: 1.65em;
    }
    .message-body.expanded {
      max-height: none;
      overflow: visible;
    }
    .expand-message {
      margin-top: 6px;
      padding: 3px 8px;
      border-radius: 999px;
      background: rgba(242, 222, 207, 0.82);
      color: #69483a;
      font-size: 12px;
    }
    .user .bubble {
      background: rgba(255, 255, 255, 0.46);
      color: rgba(61, 45, 39, 0.62);
      border: 1px solid rgba(226, 190, 166, 0.34);
      border-top-right-radius: 8px;
      box-shadow: 0 5px 14px rgba(94, 57, 37, 0.035);
    }
    .user .name {
      color: rgba(145, 120, 107, 0.7);
    }
      .deer .bubble {
        background: linear-gradient(180deg, #fffdf8, #fff7ef);
        border: 1px solid var(--border);
        border-top-left-radius: 8px;
      }
    .row.group-empathy .bubble,
    .row.group-empathic .bubble {
      max-width: min(430px, 74%);
      padding: 7px 11px;
      border-radius: 16px 16px 16px 7px;
      border: 1px solid rgba(255, 255, 255, 0.72);
      box-shadow: 0 5px 13px rgba(94, 57, 37, 0.045);
      opacity: 0.92;
    }
    .row.group-need .bubble {
      max-width: min(540px, 80%);
      padding: 8px 13px 8px 15px;
      border-radius: 14px 18px 18px 7px;
      border: 1px solid rgba(255, 255, 255, 0.78);
      border-left: 3px solid rgba(118, 148, 128, 0.32);
      box-shadow: 0 6px 15px rgba(94, 57, 37, 0.05);
      font-weight: 560;
    }
    .row.group-pinpoint .bubble {
      max-width: min(500px, 78%);
      padding: 8px 13px 8px 15px;
      border-radius: 14px 18px 18px 7px;
      border: 1px solid rgba(255, 255, 255, 0.76);
      border-left: 3px solid rgba(120, 92, 64, 0.24);
      box-shadow: 0 6px 15px rgba(94, 57, 37, 0.055);
      font-weight: 600;
    }
    .row.group-main .bubble {
      max-width: min(680px, 86%);
    }
    .row.group-anchor .bubble {
      max-width: min(460px, 76%);
      padding: 7px 12px;
      border-radius: 17px 17px 17px 7px;
      border: 1px solid rgba(255, 255, 255, 0.8);
      border-bottom: 2px solid rgba(226, 190, 166, 0.42);
      box-shadow: 0 5px 13px rgba(94, 57, 37, 0.045);
      font-weight: 600;
    }
    .row.group-empathy .message-body,
    .row.group-empathic .message-body,
    .row.group-need .message-body,
    .row.group-anchor .message-body,
    .row.group-pinpoint .message-body {
      font-size: 14px;
      line-height: 1.5;
    }
    .name {
      font-size: 12px;
      color: var(--muted);
      margin-bottom: 4px;
    }
    form {
      grid-column: 2;
      grid-row: 3;
      display: grid;
      grid-template-columns: 1fr auto auto;
      gap: 8px;
      align-items: end;
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 22px;
      padding: 9px;
      box-shadow: 0 16px 36px rgba(120, 80, 50, 0.09);
      backdrop-filter: blur(14px);
    }
    textarea {
      width: 100%;
      min-height: 44px;
      max-height: 120px;
      resize: vertical;
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 10px;
      font: inherit;
      background: white;
      color: var(--text);
    }
    button {
      border: 0;
      border-radius: 16px;
      padding: 10px 13px;
      font: inherit;
      cursor: pointer;
      background: var(--accent);
      color: white;
    }
    button.secondary {
      background: #f2decf;
      color: #69483a;
    }
    button:disabled { opacity: 0.55; cursor: not-allowed; }
    .system {
      text-align: center;
      color: var(--muted);
      font-size: 13px;
      margin: 12px 0;
      white-space: pre-wrap;
    }
    #dashboard {
      grid-column: 2 / -1;
      grid-row: 2 / -1;
      overflow-y: auto;
      background: rgba(255, 252, 246, 0.68);
      border: 1px solid var(--border);
      border-radius: 28px;
      padding: 18px;
      backdrop-filter: blur(12px);
    }
    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-bottom: 14px;
    }
    .toolbar button {
      background: #e9dac9;
      color: #4b3829;
      padding: 9px 12px;
    }
    .toolbar button.active {
      background: var(--accent);
      color: #fff;
    }
    .memory-switch {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
      margin-bottom: 12px;
    }
    .memory-switch button {
      background: #e9dac9;
      color: #4b3829;
      padding: 8px 11px;
      border-radius: 999px;
    }
    .memory-switch button.active {
      background: var(--accent);
      color: #fff;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 12px;
    }
    .stack {
      display: grid;
      gap: 14px;
    }
    .group-title {
      margin: 10px 0 4px;
      font-size: 18px;
      color: #5f3d26;
    }
    .card {
      background: rgba(255, 253, 248, 0.92);
      border: 1px solid var(--border);
      border-radius: 22px;
      padding: 14px;
      box-shadow: 0 10px 26px rgba(105, 66, 42, 0.07);
    }
    .card.clickable {
      cursor: pointer;
      transition: transform 0.12s ease, box-shadow 0.12s ease;
    }
    .card.clickable:hover {
      transform: translateY(-1px);
      box-shadow: 0 8px 22px rgba(70, 45, 20, 0.09);
    }
    .count {
      font-size: 28px;
      font-weight: 700;
      color: var(--accent);
      margin: 8px 0 2px;
    }
    .card h3 {
      margin: 0 0 8px;
      font-size: 16px;
    }
    .meta {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
      overflow-wrap: anywhere;
    }
    .content {
      margin-top: 10px;
      white-space: pre-wrap;
      line-height: 1.6;
    }
    .pill {
      display: inline-block;
      padding: 3px 8px;
      border-radius: 999px;
      background: #ffe7dc;
      color: #8a5747;
      font-size: 12px;
      margin-right: 6px;
      margin-top: 6px;
    }
    .empty {
      color: var(--muted);
      text-align: center;
      padding: 42px 8px;
    }
    .state-overview {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 18px;
      align-items: center;
      padding: 16px 0 18px;
      border-bottom: 1px solid var(--border);
    }
    .state-overview h2 {
      margin: 0 0 6px;
      font-size: 20px;
      color: #5f3d26;
    }
    .state-coverage {
      min-width: 128px;
      text-align: right;
    }
    .state-coverage strong {
      display: block;
      font-size: 25px;
      color: var(--accent);
    }
    .state-map {
      background: rgba(255, 253, 248, 0.92);
      border: 1px solid var(--border);
      border-radius: 18px;
      box-shadow: 0 8px 20px rgba(105, 66, 42, 0.055);
      overflow: hidden;
    }
    .state-domain {
      border-bottom: 1px solid var(--border);
    }
    .state-domain:last-child {
      border-bottom: 0;
    }
    .state-domain.empty-state {
      background: rgba(255, 253, 248, 0.48);
    }
    .state-domain > summary {
      display: grid;
      grid-template-columns: 112px minmax(0, 1fr) auto 14px;
      gap: 12px;
      align-items: center;
      padding: 13px 14px;
      cursor: pointer;
      list-style: none;
    }
    .state-domain > summary::-webkit-details-marker {
      display: none;
    }
    .state-domain > summary::after {
      content: "›";
      color: var(--muted);
      font-size: 18px;
      transform: rotate(0deg);
      transition: transform 0.15s ease;
    }
    .state-domain[open] > summary::after {
      transform: rotate(90deg);
    }
    .state-domain-title {
      display: flex;
      align-items: center;
      gap: 7px;
    }
    .state-domain-title strong {
      font-size: 16px;
    }
    .state-status {
      flex: 0 0 auto;
      padding: 2px 6px;
      border-radius: 999px;
      background: #e8f1e8;
      color: #55715d;
      font-size: 11px;
    }
    .empty-state .state-status {
      background: #eee7df;
      color: var(--muted);
    }
    .state-glance {
      min-width: 0;
    }
    .state-stage {
      display: block;
      margin-bottom: 2px;
      color: #4b3829;
      font-size: 13px;
      font-weight: 700;
    }
    .state-preview {
      display: -webkit-box;
      overflow: hidden;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.45;
      -webkit-box-orient: vertical;
      -webkit-line-clamp: 2;
    }
    .state-metrics {
      color: var(--muted);
      font-size: 12px;
      text-align: right;
      white-space: nowrap;
    }
    .state-domain-detail {
      padding: 0 40px 14px 138px;
    }
    .state-summary {
      margin: 0 0 10px;
      line-height: 1.65;
      white-space: pre-wrap;
    }
    .state-strategy {
      margin-top: 10px;
      padding: 9px 10px;
      border-left: 3px solid rgba(118, 148, 128, 0.38);
      background: rgba(241, 246, 239, 0.68);
      line-height: 1.55;
    }
    .state-evidence {
      margin-top: 8px;
    }
    .state-history {
      margin-top: 12px;
      border-top: 1px solid var(--border);
      padding-top: 10px;
    }
    .state-history summary {
      color: #6f4a3e;
      cursor: pointer;
      font-size: 13px;
      font-weight: 700;
    }
    .state-version {
      padding: 11px 0;
      border-bottom: 1px dashed var(--border);
    }
    .state-version:last-child {
      border-bottom: 0;
    }
    .state-version-title {
      margin: 4px 0;
      font-weight: 700;
    }
    @media (max-width: 760px) {
      .state-overview {
        grid-template-columns: 1fr;
      }
      .state-coverage {
        text-align: left;
      }
      .state-domain > summary {
        grid-template-columns: minmax(0, 1fr) auto 14px;
        gap: 7px;
      }
      .state-domain-title {
        grid-column: 1;
      }
      .state-glance {
        grid-column: 1 / -1;
        grid-row: 2;
      }
      .state-metrics {
        grid-column: 2;
        grid-row: 1;
      }
      .state-domain > summary::after {
        grid-column: 3;
        grid-row: 1;
      }
      .state-domain-detail {
        padding: 0 14px 14px;
      }
    }
    .chart {
      background: #fff;
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 14px;
      margin-bottom: 14px;
    }
    .bars {
      display: flex;
      gap: 6px;
      align-items: end;
      height: 160px;
      border-bottom: 1px solid var(--border);
      padding: 8px 4px 0;
    }
    .bar {
      flex: 1;
      min-width: 12px;
      border-radius: 8px 8px 0 0;
      background: #d9c6b4;
      position: relative;
    }
    .bar.positive { background: #91c7a9; }
    .bar.negative { background: #d79a8b; }
    .bar.neutral { background: #d9c6b4; }
    .calendar {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
      gap: 8px;
    }
    .day {
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 10px;
      background: #fff;
      min-height: 82px;
    }
    .day.good { background: #e8f5ed; }
    .day.bad { background: #f8e8e3; }
    .day.neutral { background: #fffaf3; }
    .used-cards {
      margin-top: 10px;
      padding-top: 8px;
      border-top: 1px dashed var(--border);
    }
    .used-card {
      display: inline-block;
      margin: 4px 6px 0 0;
      padding: 4px 8px;
      border-radius: 999px;
      background: #f2e5d6;
      color: #6f4a31;
      font-size: 12px;
    }
    .hero-card {
      grid-column: 1 / -1;
      background: linear-gradient(135deg, rgba(255, 249, 236, 0.96), rgba(255, 224, 211, 0.92));
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 18px;
    }
    .content-type {
      text-transform: uppercase;
      letter-spacing: 0.06em;
      font-size: 11px;
      color: var(--muted);
    }
    .detail-panel {
      position: fixed;
      right: 18px;
      bottom: 18px;
      width: min(460px, calc(100vw - 36px));
      max-height: 78vh;
      overflow-y: auto;
      background: #fffaf3;
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 16px;
      box-shadow: 0 18px 46px rgba(70, 45, 20, 0.18);
      z-index: 10;
    }
    .detail-header {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      align-items: start;
    }
    .panel-title {
      margin: 0 0 8px;
      font-size: 15px;
      color: #5f3d26;
    }
    .animal-states {
      display: grid;
      gap: 8px;
    }
    .animal-state {
      display: grid;
      grid-template-columns: 44px 1fr;
      gap: 9px;
      align-items: center;
      padding: 9px;
      border-radius: 18px;
      background: rgba(255, 248, 239, 0.78);
      border: 1px solid rgba(226, 190, 166, 0.56);
      cursor: pointer;
      text-align: left;
      color: var(--text);
    }
    .animal-state.active {
      background: linear-gradient(135deg, #fff0d6, #ffe0de);
      box-shadow: 0 8px 18px rgba(147, 91, 65, 0.1);
    }
    .animal-panel.auto-mode .animal-state {
      opacity: 0.84;
    }
    .state-avatar {
      width: 42px;
      height: 42px;
      border-radius: 15px;
      object-fit: cover;
      background: #fff;
      border: 1px solid rgba(255, 253, 248, 0.92);
      box-shadow: 0 7px 15px rgba(140, 92, 72, 0.1);
    }
    .state-avatar-wrap {
      position: relative;
      width: 42px;
      height: 42px;
    }
    .state-face-badge {
      position: absolute;
      right: -5px;
      bottom: -5px;
      display: grid;
      place-items: center;
      width: 21px;
      height: 21px;
      border-radius: 999px;
      background: rgba(255, 253, 248, 0.96);
      border: 1px solid rgba(226, 190, 166, 0.7);
      font-size: 13px;
      box-shadow: 0 4px 10px rgba(120, 80, 50, 0.12);
    }
    .state-name {
      font-size: 13px;
      font-weight: 700;
    }
    .state-line {
      color: var(--muted);
      font-size: 11px;
      line-height: 1.35;
    }
    @media (max-width: 720px) {
      body {
        background-attachment: scroll;
      }
      .app {
        width: 100vw;
        min-height: 100dvh;
        height: 100dvh;
        grid-template-columns: 1fr;
        grid-template-rows: auto auto minmax(0, 1fr) auto;
        padding: 8px;
        gap: 8px;
        overflow: hidden;
      }
      .top-bar {
        grid-column: 1;
        grid-row: 1;
        min-height: 52px;
        padding: 9px 12px;
        border-radius: 20px;
      }
      .app-title-name {
        font-size: 16px;
      }
      .app-title-subtitle,
      .app-scene-note {
        display: none;
      }
      .control-panel {
        grid-column: 1;
        grid-row: 2;
        border-radius: 20px;
        padding: 9px;
        max-height: 238px;
        overflow-y: auto;
        -webkit-overflow-scrolling: touch;
      }
      .animal-panel {
        display: none;
      }
      #messages {
        grid-column: 1;
        grid-row: 3;
        min-height: 0;
        overflow-y: auto;
      }
      #dashboard {
        grid-column: 1;
        grid-row: 3 / -1;
      }
      form {
        grid-column: 1;
        grid-row: 4;
        position: relative;
        z-index: 2;
      }
      .brand {
        gap: 10px;
        align-items: flex-start;
      }
      .deer-logo {
        width: 40px;
        height: 40px;
        border-radius: 15px;
      }
      h1 {
        font-size: 17px;
        line-height: 1.25;
      }
      .subtitle {
        font-size: 12px;
      }
      nav {
        display: grid;
        grid-template-columns: 1fr 1fr;
      }
      .tab {
        width: 100%;
        padding: 9px 10px;
      }
      .character-strip {
        display: grid;
        grid-template-columns: repeat(6, minmax(0, 1fr));
        gap: 6px;
      }
      .quick-title,
      .sidebar-section-title {
        margin-top: 8px;
      }
      .cozy-list {
        gap: 6px;
      }
      .cozy-card {
        padding: 7px 6px;
        border-radius: 15px;
      }
      .cozy-text {
        display: none;
      }
      .settings-title,
      .settings-list {
        display: none;
      }
      .selected-animal-card {
        margin-top: 7px;
        padding: 8px;
        border-radius: 18px;
      }
      .selected-animal-top {
        grid-template-columns: 52px 1fr;
        gap: 8px;
      }
      .selected-animal-avatar {
        width: 52px;
        height: 58px;
        border-radius: 16px;
      }
      .selected-animal-intro {
        display: none;
      }
      .character-button {
        padding: 5px 4px;
      }
      .character-avatar {
        width: 30px;
        height: 30px;
        border-radius: 12px;
      }
      .character-name {
        font-size: 11px;
      }
      .character-voice {
        display: none;
      }
      #messages,
      #dashboard {
        border-radius: 22px;
        padding: 12px;
      }
      .row {
        margin: 8px 0;
      }
      .avatar {
        width: 34px;
        height: 34px;
        border-radius: 13px;
      }
      .bubble {
        max-width: 88%;
        padding: 9px 11px;
        border-radius: 18px;
        line-height: 1.5;
        font-size: 15px;
      }
      form {
        grid-template-columns: 1fr 1fr;
        border-radius: 22px;
        padding: 10px;
      }
      textarea {
        grid-column: 1 / -1;
        min-height: 58px;
        max-height: 110px;
        font-size: 16px;
      }
      #send,
      #end {
        width: 100%;
        padding: 11px 10px;
      }
      .toolbar {
        flex-wrap: nowrap;
        overflow-x: auto;
        padding-bottom: 4px;
        -webkit-overflow-scrolling: touch;
      }
      .toolbar button {
        flex: 0 0 auto;
      }
      .grid {
        grid-template-columns: 1fr;
      }
      .calendar {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .detail-panel {
        left: 10px;
        right: 10px;
        bottom: 10px;
        width: auto;
        max-height: 70vh;
      }
      .dev-panel {
        left: 10px;
        right: 10px;
        top: 72px;
        width: auto;
        max-height: calc(100dvh - 92px);
      }
    }
  </style>
</head>
<body>
  <main class="app">
    <header class="top-bar" aria-label="应用标题">
      <div class="app-title">
        <div class="app-title-mark" aria-hidden="true">🌙</div>
        <div class="app-title-text">
          <div class="app-title-name">小动物夜谈会</div>
          <div class="app-title-subtitle">夜空、树影和几只正在值班的小动物。</div>
        </div>
      </div>
      <div class="app-scene-note">今晚可以慢慢说。</div>
    </header>
    <aside id="controlsPanel" class="control-panel">
      <div class="panel-heading">
        <h1>控制面板</h1>
        <span class="panel-dot" aria-hidden="true"></span>
      </div>
      <nav>
        <button id="chatTab" class="tab active" type="button">对话</button>
        <button id="dataTab" class="tab" type="button">看板</button>
      </nav>
      <div class="quick-title">今日快捷</div>
      <div class="cozy-list" aria-label="今日小卡片">
        <button id="stateShortcut" class="cozy-card clickable" type="button">
          <div class="cozy-title">🧭 心理地图</div>
          <div class="cozy-text">长期状态</div>
        </button>
        <button id="journalShortcut" class="cozy-card clickable" type="button">
          <div class="cozy-title">📔 日记</div>
          <div class="cozy-text">过往记录</div>
        </button>
        <button id="moodShortcut" class="cozy-card clickable" type="button">
          <div class="cozy-title">🌙 月历</div>
          <div class="cozy-text">心情轨迹</div>
        </button>
        <button id="chatShortcut" class="cozy-card clickable" type="button">
          <div class="cozy-title">💬 聊天</div>
          <div class="cozy-text">回到对话</div>
        </button>
      </div>
      <div class="sidebar-section-title current-role-title">当前形态</div>
      <section id="selectedAnimalCard" class="selected-animal-card" aria-label="当前兔子形态"></section>
      <div id="characterStrip" class="character-strip" aria-label="选择兔子形态"></div>
      <div class="sidebar-section-title settings-title">设置</div>
      <div class="settings-list" aria-label="设置入口">
        <button class="settings-item" type="button">
          <span>角色设置</span>
          <span class="settings-arrow">›</span>
        </button>
        <button class="settings-item" type="button">
          <span>系统设置</span>
          <span class="settings-arrow">›</span>
        </button>
        <button id="devPanelToggle" class="settings-item" type="button">
          <span>开发面板</span>
          <span class="settings-arrow">›</span>
        </button>
      </div>
    </aside>
    <section id="messages" class="view"></section>
    <aside id="animalPanel" class="animal-panel">
      <h2 class="panel-title">兔子形态</h2>
      <button id="groupToggle" class="group-toggle" type="button" aria-pressed="false">
        <span>
          <span class="toggle-label">自动形态</span>
          <span class="toggle-note">让 DeepSeek 选择形态和表情</span>
        </span>
        <span id="groupTogglePill" class="toggle-pill">关</span>
      </button>
      <div id="animalStates" class="animal-states"></div>
    </aside>
    <section id="dashboard" class="view hidden">
      <div class="toolbar">
        <button data-view="state" class="active" type="button">心理地图</button>
        <button data-view="sessions" type="button">Sessions</button>
        <button data-view="memories" type="button">Memories</button>
        <button data-view="knowledge" type="button">Knowledge</button>
        <button data-view="content" type="button">Content</button>
        <button data-view="mood" type="button">Mood</button>
        <button data-view="journals" type="button">Journals</button>
        <button data-view="messages" type="button">Messages</button>
        <button id="refreshData" type="button">刷新</button>
        <button id="cleanupSessions" type="button">清理空 Sessions</button>
      </div>
      <div id="dataList" class="grid"></div>
    </section>
    <aside id="detailPanel" class="detail-panel hidden"></aside>
    <aside id="devPanel" class="dev-panel hidden" aria-label="开发者调试面板"></aside>
    <form id="form">
      <textarea id="input" placeholder="把此刻想说的话写在这里。Shift+Enter 换行，Enter 发送。"></textarea>
      <button id="send" type="submit">发送</button>
      <button id="end" class="secondary" type="button">结束并总结</button>
    </form>
  </main>
  <script>
    const messages = document.querySelector("#messages");
    const input = document.querySelector("#input");
    const form = document.querySelector("#form");
    const send = document.querySelector("#send");
    const end = document.querySelector("#end");
    const chatTab = document.querySelector("#chatTab");
    const dataTab = document.querySelector("#dataTab");
    const groupToggle = document.querySelector("#groupToggle");
    const groupTogglePill = document.querySelector("#groupTogglePill");
    const moodShortcut = document.querySelector("#moodShortcut");
    const journalShortcut = document.querySelector("#journalShortcut");
    const chatShortcut = document.querySelector("#chatShortcut");
    const stateShortcut = document.querySelector("#stateShortcut");
    const selectedAnimalCard = document.querySelector("#selectedAnimalCard");
    const characterStrip = document.querySelector("#characterStrip");
    const controlsPanel = document.querySelector("#controlsPanel");
    const animalPanel = document.querySelector("#animalPanel");
    const animalStates = document.querySelector("#animalStates");
    const dashboard = document.querySelector("#dashboard");
    const dataList = document.querySelector("#dataList");
    const detailPanel = document.querySelector("#detailPanel");
    const devPanel = document.querySelector("#devPanel");
    const devPanelToggle = document.querySelector("#devPanelToggle");
    const refreshData = document.querySelector("#refreshData");
    const cleanupSessions = document.querySelector("#cleanupSessions");
    const dataButtons = [...document.querySelectorAll("[data-view]")];

    let sessionId = null;
    let busy = false;
    let activeDataView = "state";
    let memoryItems = [];
    let memoryViewMode = "taxonomy";
    let lastDebugTrace = null;
    const CHARACTERS = __CHARACTERS_JSON__;
    const LEGACY_CHARACTER_ALIASES = {
      sensen_deer: "yoyo",
      youyou_rabbit: "yoyo",
      gugu_bear: "momo",
      gangan_tiger: "momo",
      huahua_fox: "yoran",
      shanshan_butterfly: "yoran"
    };
    let activeCharacterId = localStorage.getItem("xiaolu.character") || "yoyo";
    let replyMode = localStorage.getItem("xiaolu.replyMode") || "manual";
    const defaultAnimalState = {
      yoyo: { mood: "在倾听", need: "先陪你把感受放下来", face: "🌙" },
      momo: { mood: "准备好", need: "陪你慢慢试试看", face: "☁️" },
      yoran: { mood: "很平静", need: "帮你把感受和行动放在一起", face: "✨" }
    };
    let animalState = JSON.parse(JSON.stringify(defaultAnimalState));

    function currentCharacter() {
      activeCharacterId = LEGACY_CHARACTER_ALIASES[activeCharacterId] || activeCharacterId;
      const character = CHARACTERS.find(item => item.id === activeCharacterId);
      if (character) return character;
      activeCharacterId = CHARACTERS[0].id;
      localStorage.setItem("xiaolu.character", activeCharacterId);
      return CHARACTERS[0];
    }

    function characterById(characterId) {
      const normalizedId = LEGACY_CHARACTER_ALIASES[characterId] || characterId;
      return CHARACTERS.find(item => item.id === normalizedId) || CHARACTERS[0];
    }

    function expressionFor(character, expressionId = "") {
      const expressions = character.expressions || {};
      const selectedId = expressionId && expressions[expressionId]
        ? expressionId
        : (character.default_expression_id || Object.keys(expressions)[0] || "");
      return {
        id: selectedId,
        ...(expressions[selectedId] || {}),
      };
    }

    function routePlanSummary(plan) {
      if (!plan) return "";
      if (plan.character_id) {
        const character = characterById(plan.character_id);
        const expression = expressionFor(character, plan.expression_id);
        const mode = plan.response_mode ? ` · ${plan.response_mode}` : "";
        return `本轮规划${mode}：${character.name} · ${expression.label || expression.id || "默认表情"}；${plan.reason || "根据用户此刻状态自动选择"}`;
      }
      if (!plan.main) return "";
      const empathy = characterById((plan.empathy || plan.empathic)?.character_id);
      const need = characterById((plan.need || plan.pinpoint)?.character_id);
      const main = characterById(plan.main?.character_id);
      const anchor = plan.anchor ? characterById(plan.anchor?.character_id) : null;
      const mode = plan.response_mode ? ` · ${plan.response_mode}` : "";
      const anchorText = anchor ? `，${anchor.name}收束` : "";
      return `本轮规划${mode}：${empathy.name}共情，${need.name}点明需求，${main.name}主回复${anchorText}`;
    }

    function formatJson(value) {
      return escapeHtml(JSON.stringify(value ?? {}, null, 2));
    }

    function renderTurnPlan(plan) {
      if (!plan) return "";
      const needs = Array.isArray(plan.knowledge_needs) ? plan.knowledge_needs : [];
      const memoryQueries = Array.isArray(plan.memory_queries) ? plan.memory_queries : [];
      const knowledgeQueries = Array.isArray(plan.knowledge_queries) ? plan.knowledge_queries : [];
      if (plan.character_id) {
        const character = characterById(plan.character_id);
        const expression = expressionFor(character, plan.expression_id);
        return `
          <div class="dev-section">
            <h3>本轮策略规划</h3>
            <div class="dev-plan-grid">
              <div class="dev-plan-cell">
                <div class="dev-plan-label">用户状态</div>
                <div class="dev-plan-value">${escapeHtml(plan.user_state || "-")}</div>
              </div>
              <div class="dev-plan-cell">
                <div class="dev-plan-label">核心需要</div>
                <div class="dev-plan-value">${escapeHtml(plan.core_need || "-")}</div>
              </div>
              <div class="dev-plan-cell">
                <div class="dev-plan-label">风险等级</div>
                <div class="dev-plan-value">${escapeHtml(plan.risk_level || "-")}</div>
              </div>
              <div class="dev-plan-cell">
                <div class="dev-plan-label">回复模式</div>
                <div class="dev-plan-value">${escapeHtml(plan.response_mode || "-")}</div>
              </div>
              <div class="dev-plan-cell">
                <div class="dev-plan-label">兔子形态</div>
                <div class="dev-plan-value">${escapeHtml(character.name)} · ${escapeHtml(character.animal || "")}</div>
              </div>
              <div class="dev-plan-cell">
                <div class="dev-plan-label">表情</div>
                <div class="dev-plan-value">${escapeHtml(expression.id || "-")} · ${escapeHtml(expression.label || "-")}</div>
              </div>
              <div class="dev-plan-cell">
                <div class="dev-plan-label">知识需要</div>
                <div class="dev-tags">
                  ${needs.length ? needs.map(item => `<span class="dev-tag">${escapeHtml(item)}</span>`).join("") : '<span class="dev-plan-value">暂无</span>'}
                </div>
              </div>
              <div class="dev-plan-cell">
                <div class="dev-plan-label">记忆检索词</div>
                <div class="dev-tags">
                  ${memoryQueries.length ? memoryQueries.map(item => `<span class="dev-tag">${escapeHtml(item)}</span>`).join("") : '<span class="dev-plan-value">暂无</span>'}
                </div>
              </div>
              <div class="dev-plan-cell">
                <div class="dev-plan-label">知识检索词</div>
                <div class="dev-tags">
                  ${knowledgeQueries.length ? knowledgeQueries.map(item => `<span class="dev-tag">${escapeHtml(item)}</span>`).join("") : '<span class="dev-plan-value">暂无</span>'}
                </div>
              </div>
            </div>
            <div class="dev-item" style="margin-top: 7px;">
              <div class="dev-plan-label">写作提醒</div>
              <div class="dev-plan-value">${escapeHtml(plan.response_guidance || "-")}</div>
            </div>
            <div class="dev-item" style="margin-top: 7px;">
              <div class="dev-plan-label">选择理由</div>
              <div class="dev-plan-value">${escapeHtml(plan.reason || "-")}</div>
            </div>
          </div>
        `;
      }
      const empathy = characterById((plan.empathy || plan.empathic)?.character_id);
      const need = characterById((plan.need || plan.pinpoint)?.character_id);
      const main = characterById(plan.main?.character_id);
      const anchor = plan.anchor ? characterById(plan.anchor?.character_id) : null;
      return `
        <div class="dev-section">
          <h3>本轮策略规划</h3>
          <div class="dev-plan-grid">
            <div class="dev-plan-cell">
              <div class="dev-plan-label">用户状态</div>
              <div class="dev-plan-value">${escapeHtml(plan.user_state || "-")}</div>
            </div>
            <div class="dev-plan-cell">
              <div class="dev-plan-label">核心需要</div>
              <div class="dev-plan-value">${escapeHtml(plan.core_need || "-")}</div>
            </div>
            <div class="dev-plan-cell">
              <div class="dev-plan-label">风险等级</div>
              <div class="dev-plan-value">${escapeHtml(plan.risk_level || "-")}</div>
            </div>
            <div class="dev-plan-cell">
              <div class="dev-plan-label">回复模式</div>
              <div class="dev-plan-value">${escapeHtml(plan.response_mode || "-")}</div>
            </div>
            <div class="dev-plan-cell">
              <div class="dev-plan-label">角色分工</div>
              <div class="dev-plan-value">${escapeHtml(empathy.name)}共情 · ${escapeHtml(need.name)}需求 · ${escapeHtml(main.name)}主回复${anchor ? " · " + escapeHtml(anchor.name) + "收束" : ""}</div>
            </div>
            <div class="dev-plan-cell">
              <div class="dev-plan-label">知识需要</div>
              <div class="dev-tags">
                ${needs.length ? needs.map(item => `<span class="dev-tag">${escapeHtml(item)}</span>`).join("") : '<span class="dev-plan-value">暂无</span>'}
              </div>
            </div>
            <div class="dev-plan-cell">
              <div class="dev-plan-label">记忆检索词</div>
              <div class="dev-tags">
                ${memoryQueries.length ? memoryQueries.map(item => `<span class="dev-tag">${escapeHtml(item)}</span>`).join("") : '<span class="dev-plan-value">暂无</span>'}
              </div>
            </div>
            <div class="dev-plan-cell">
              <div class="dev-plan-label">知识检索词</div>
              <div class="dev-tags">
                ${knowledgeQueries.length ? knowledgeQueries.map(item => `<span class="dev-tag">${escapeHtml(item)}</span>`).join("") : '<span class="dev-plan-value">暂无</span>'}
              </div>
            </div>
          </div>
          <div class="dev-item" style="margin-top: 7px;">
            <div class="dev-plan-label">写作提醒</div>
            <div class="dev-plan-value">${escapeHtml(plan.response_guidance || "-")}</div>
          </div>
        </div>
      `;
    }

    function renderDevPanel(trace = lastDebugTrace) {
      if (!trace) {
        devPanel.innerHTML = `
          <div class="dev-panel-header">
            <h2>开发面板</h2>
            <button type="button" onclick="window.closeDevPanel()">关闭</button>
          </div>
          <div class="empty">还没有本轮调试信息。发送一条消息后这里会显示后台流程。</div>
        `;
        return;
      }
      const calls = trace.llm_calls || [];
      const steps = trace.steps || [];
      const turnPlan = steps.find(step => step.name === "turn_planner" && step.output)?.output;
      devPanel.innerHTML = `
        <div class="dev-panel-header">
          <div>
            <h2>开发面板</h2>
            <div class="meta">${escapeHtml(trace.mode)} · LLM ${trace.llm_call_count ?? calls.length} 次 · ${trace.total_elapsed_sec ?? "-"}s</div>
          </div>
          <button type="button" onclick="window.closeDevPanel()">关闭</button>
        </div>
        ${renderTurnPlan(turnPlan)}
        <div class="dev-section">
          <h3>流程步骤</h3>
          <div class="dev-list">
            ${steps.map((step, index) => `
              <div class="dev-item">
                <div><b>${index + 1}. ${escapeHtml(step.name)}</b> · ${escapeHtml(step.status || "-")}</div>
                <div class="meta">${escapeHtml(step.summary || "")}</div>
                ${step.output ? `<pre class="dev-pre">${formatJson(step.output)}</pre>` : ""}
              </div>
            `).join("") || '<div class="meta">无步骤记录。</div>'}
          </div>
        </div>
        <div class="dev-section">
          <h3>LLM 调用</h3>
          <div class="dev-list">
            ${calls.map((call, index) => `
              <div class="dev-item">
                <div><b>${index + 1}. ${escapeHtml(call.name)}</b> · ${escapeHtml(call.model || "-")} · ${escapeHtml(call.elapsed_sec ?? "-")}s</div>
                <div class="meta">format: ${escapeHtml(call.response_format || "text")}</div>
                ${call.error ? `<div class="meta">error: ${escapeHtml(call.error)}</div>` : ""}
                ${call.parsed_output ? `<div class="meta">parsed output</div><pre class="dev-pre">${formatJson(call.parsed_output)}</pre>` : ""}
                ${call.raw_output ? `<div class="meta">raw output</div><pre class="dev-pre">${escapeHtml(call.raw_output)}</pre>` : ""}
              </div>
            `).join("") || '<div class="meta">无 LLM 调用记录。</div>'}
          </div>
        </div>
      `;
    }

    window.closeDevPanel = function() {
      devPanel.classList.add("hidden");
    }

    function renderCharacters() {
      characterStrip.innerHTML = CHARACTERS.map(character => `
        <button class="character-button ${replyMode === "manual" && character.id === activeCharacterId ? "active" : ""}" type="button" data-character="${escapeHtml(character.id)}" title="${escapeHtml(character.tagline)}">
          <img class="character-avatar" src="${escapeHtml(character.avatar_path)}" alt="${escapeHtml(character.name)}头像" />
          <span class="character-name">${escapeHtml(character.name)}</span>
          <span class="character-voice">${escapeHtml(character.voice)}</span>
        </button>
      `).join("");
      characterStrip.querySelectorAll("[data-character]").forEach(button => {
        button.addEventListener("click", () => selectCharacter(button.dataset.character));
      });
      characterStrip.classList.toggle("auto-mode", replyMode === "auto");
      animalPanel.classList.toggle("auto-mode", replyMode === "auto");
      renderAnimalStates(activeCharacterId);
      renderSelectedAnimalCard();
    }

    function selectCharacter(characterId) {
      setReplyMode("manual");
      activeCharacterId = characterId;
      localStorage.setItem("xiaolu.character", activeCharacterId);
      updateCharacterBrand();
      renderCharacters();
    }

    function setReplyMode(mode) {
      replyMode = mode;
      localStorage.setItem("xiaolu.replyMode", replyMode);
      groupToggle.classList.toggle("active", replyMode === "auto");
      groupToggle.setAttribute("aria-pressed", replyMode === "auto" ? "true" : "false");
      groupTogglePill.textContent = replyMode === "auto" ? "开" : "关";
      renderCharacters();
    }

    function updateCharacterBrand() {
      renderSelectedAnimalCard();
    }

    function stateForText(text, characterId) {
      const content = text || "";
      if (content.includes("难过") || content.includes("想哭") || content.includes("痛苦") || content.includes("心疼") || content.includes("抱抱")) {
        return { mood: "很共情", need: "轻轻靠近你的难过", face: "🥺" };
      }
      if (content.includes("焦虑") || content.includes("慌") || content.includes("撑不住") || content.includes("慢慢") || content.includes("稳")) {
        return { mood: "稳住中", need: "帮你慢慢落地", face: "🫶" };
      }
      if (content.includes("生气") || content.includes("不公平") || content.includes("边界") || content.includes("保护") || content.includes("勇敢")) {
        return { mood: "认真起来", need: "保护你的边界", face: "🛡️" };
      }
      if (content.includes("看见") || content.includes("模式") || content.includes("理解") || content.includes("线索") || content.includes("清楚")) {
        return { mood: "在思考", need: "帮你看清线索", face: "🧐" };
      }
      if (content.includes("开心") || content.includes("希望") || content.includes("试试") || content.includes("轻一点") || content.includes("亮")) {
        return { mood: "亮了一点", need: "想陪你往前走一点", face: "🌟" };
      }
      return {
        mood: defaultAnimalState[characterId]?.mood || "在听",
        need: defaultAnimalState[characterId]?.need || "正在陪你",
        face: defaultAnimalState[characterId]?.face || "🍃"
      };
    }

    function renderSelectedAnimalCard() {
      const character = currentCharacter();
      const state = animalState[character.id] || defaultAnimalState[character.id] || {};
      selectedAnimalCard.innerHTML = `
        <div class="selected-animal-top">
          <img class="selected-animal-avatar" src="${escapeHtml(character.showcase_avatar_path || character.status_avatar_path || character.avatar_path)}" alt="${escapeHtml(character.name)}展示图" />
          <div>
            <div class="selected-animal-name">${escapeHtml(character.name)} ${escapeHtml(state.face || "🍃")}</div>
            <div class="selected-animal-mood">${escapeHtml(state.mood || "在听")}</div>
          </div>
        </div>
        <div class="selected-animal-intro">${escapeHtml(character.tagline)}<br>${escapeHtml(state.need || character.voice)}</div>
      `;
    }

    function renderAnimalStates(activeId = activeCharacterId) {
      animalStates.innerHTML = CHARACTERS.map(character => {
        const state = animalState[character.id] || defaultAnimalState[character.id] || {};
        const active = character.id === activeId || (replyMode === "manual" && character.id === activeCharacterId);
        return `
            <button class="animal-state ${active ? "active" : ""}" type="button" data-state-character="${escapeHtml(character.id)}">
            <div class="state-avatar-wrap">
              <img class="state-avatar" src="${escapeHtml(character.avatar_path)}" alt="${escapeHtml(character.name)}头像" style="background: ${escapeHtml(character.bubble_color)}; border-color: ${escapeHtml(character.bubble_color)};" />
              <span class="state-face-badge">${escapeHtml(state.face || "🍃")}</span>
            </div>
            <div>
              <div class="state-name">${escapeHtml(character.name)}</div>
              <div class="state-line">${escapeHtml(state.mood || "在听")}</div>
              <div class="state-line">${escapeHtml(state.need || character.voice)}</div>
            </div>
            </button>
        `;
      }).join("");
      animalStates.querySelectorAll("[data-state-character]").forEach(button => {
        button.addEventListener("click", () => selectCharacter(button.dataset.stateCharacter));
      });
    }

    function updateAnimalState(characterId, text) {
      animalState[characterId] = stateForText(text, characterId);
      renderAnimalStates(characterId);
      if (characterId === activeCharacterId) renderSelectedAnimalCard();
    }

    function setBusy(value) {
      busy = value;
      send.disabled = value;
      end.disabled = value;
      input.disabled = value;
      send.textContent = value ? "等待中..." : "发送";
    }

    function actionIcon(action) {
      const icons = {
        soft_lean: "↘",
        tilt_head: "⌁",
        slow_nod: "⌄",
        warm_glow: "✦",
        steady_guard: "●",
        small_breath: "◦"
      };
      return icons[action] || "";
    }

    function addMessage(role, text, knowledgeCards = [], characterId = null, options = {}) {
      const character = characterId ? characterById(characterId) : CHARACTERS[0];
      const expression = role === "user" ? null : expressionFor(character, options.expressionId || options.expression_id || "");
      const groupRole = options.groupRole || "";
      const action = options.action || "";
      const row = document.createElement("div");
      row.className = "row " + (role === "user" ? "user" : "deer");
      if (groupRole) row.classList.add("group-" + groupRole);
      if (role !== "user") {
        const avatarWrap = document.createElement("div");
        avatarWrap.className = "avatar-wrap";
        if (action) avatarWrap.dataset.action = action;
        let avatar;
        const avatarPath = expression?.path || character.avatar_path;
        if (avatarPath) {
          avatar = document.createElement("img");
          avatar.src = avatarPath;
          avatar.style.background = character.bubble_color || "#fff";
          avatar.style.borderColor = character.bubble_color || "rgba(255, 255, 255, 0.9)";
        } else {
          avatar = document.createElement("div");
          avatar.className = "avatar emoji-avatar";
          avatar.textContent = character.emoji;
          avatar.style.background = character.bubble_color || "#fff";
        }
        avatar.classList.add("avatar");
        avatar.alt = character.name;
        avatarWrap.appendChild(avatar);
        const icon = actionIcon(action);
        if (icon) {
          const actionBadge = document.createElement("span");
          actionBadge.className = "avatar-action";
          actionBadge.textContent = icon;
          avatarWrap.appendChild(actionBadge);
        }
        row.appendChild(avatarWrap);
      }
      const bubble = document.createElement("div");
      bubble.className = "bubble";
      if (role !== "user" && character.bubble_color) {
        bubble.style.background = character.bubble_color;
      }
      const head = document.createElement("div");
      head.className = "message-head";
      const face = document.createElement("span");
      face.className = "message-face";
      face.textContent = role === "user" ? "🫧" : (animalState[character.id]?.face || character.emoji || "🍃");
      const name = document.createElement("div");
      name.className = "name";
      name.textContent = role === "user" ? "你" : `${character.name}${expression?.label ? " · " + expression.label : ""}`;
      head.appendChild(face);
      head.appendChild(name);
      const body = document.createElement("div");
      body.className = "message-body";
      body.textContent = text;
      const compactGroupRole = ["empathy", "empathic", "need", "pinpoint", "anchor"].includes(groupRole);
      if (!(role !== "user" && compactGroupRole)) {
        bubble.appendChild(head);
      }
      bubble.appendChild(body);
      const shouldCollapse = !compactGroupRole && (text.length > 80 || text.includes("\\n"));
      if (shouldCollapse) {
        body.classList.add("collapsed");
        const toggle = document.createElement("button");
        toggle.type = "button";
        toggle.className = "expand-message";
        toggle.textContent = "展开";
        toggle.addEventListener("click", () => {
          const expanded = body.classList.toggle("expanded");
          body.classList.toggle("collapsed", !expanded);
          toggle.textContent = expanded ? "收起" : "展开";
        });
        bubble.appendChild(toggle);
      } else {
        body.classList.add("expanded");
      }
      if (knowledgeCards.length) {
        const cards = document.createElement("div");
        cards.className = "used-cards";
        const label = document.createElement("div");
        label.className = "meta";
        label.textContent = "本轮参考知识卡";
        cards.appendChild(label);
        for (const card of knowledgeCards) {
          const tag = document.createElement("span");
          tag.className = "used-card";
          tag.textContent = card.title;
          tag.title = card.concept || "";
          tag.onclick = () => showKnowledgeDetail(card.id);
          cards.appendChild(tag);
        }
        bubble.appendChild(cards);
      }
      row.appendChild(bubble);
      messages.appendChild(row);
      messages.scrollTop = messages.scrollHeight;
    }

    function addSystem(text) {
      const node = document.createElement("div");
      node.className = "system";
      node.textContent = text;
      messages.appendChild(node);
      messages.scrollTop = messages.scrollHeight;
    }

    const WEB_TIMEOUT_MS = __WEB_TIMEOUT_MS__;
    const END_TIMEOUT_MS = Math.max(WEB_TIMEOUT_MS, 90000);

    async function post(path, payload = {}, timeoutMs = WEB_TIMEOUT_MS) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      let response;
      try {
        response = await fetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      } catch (error) {
        if (error.name === "AbortError") {
          throw new Error("请求超过 " + Math.round(timeoutMs / 1000) + " 秒未返回。请看 logs/app.log 判断是模型超时还是网络问题。");
        }
        throw error;
      } finally {
        clearTimeout(timer);
      }
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "请求失败");
      return data;
    }

    async function get(path) {
      const response = await fetch(path);
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "请求失败");
      return data;
    }

    function closeDetail() {
      detailPanel.classList.add("hidden");
      detailPanel.innerHTML = "";
    }

    function renderContentMini(cards) {
      if (!cards.length) {
        return '<div class="meta">还没有关联内容卡。</div>';
      }
      return cards.map(item => `
        <article class="card">
          <div class="content-type">${escapeHtml(item.type)}</div>
          <h3>${escapeHtml(item.title)}</h3>
          <div class="meta">${escapeHtml(item.creator)}</div>
          <div class="content">${escapeHtml(item.fit_for)}</div>
          <div class="meta">小鹿用法：${escapeHtml(item.xiaolu_note)}</div>
          ${item.source_url ? `<a href="${escapeHtml(item.source_url)}" target="_blank" rel="noreferrer">打开来源</a>` : ""}
        </article>
      `).join("");
    }

    async function showKnowledgeDetail(cardId) {
      const data = await get("/api/knowledge_detail?id=" + encodeURIComponent(cardId));
      detailPanel.classList.remove("hidden");
      detailPanel.innerHTML = `
        <div class="detail-header">
          <div>
            <div class="content-type">knowledge</div>
            <h2 class="group-title">${escapeHtml(data.card.title)}</h2>
          </div>
          <button type="button" onclick="closeDetail()">关闭</button>
        </div>
        <div class="meta">domain: ${escapeHtml(data.card.domain)} · source: ${escapeHtml(data.card.source)}</div>
        <div>${(data.card.tags || []).map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("")}</div>
        <div class="content">${escapeHtml(data.card.concept)}</div>
        <div class="meta">适用：${escapeHtml(data.card.use_when)}</div>
        <div class="meta">小鹿表达：${escapeHtml(data.card.xiaolu_style)}</div>
        <h3>相关内容</h3>
        <div class="stack">${renderContentMini(data.related_content || [])}</div>
      `;
    }

    window.closeDetail = closeDetail;

    async function ensureSession() {
      if (sessionId) return sessionId;
      const data = await post("/api/session");
      sessionId = data.session_id;
      return sessionId;
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (busy) return;
      const text = input.value.trim();
      if (!text) return;
      input.value = "";
      const sendingCharacterId = replyMode === "auto" ? "auto" : activeCharacterId;
      const thinkingName = replyMode === "auto" ? "森森兔" : currentCharacter().name;
      setBusy(true);
      try {
        const currentSessionId = await ensureSession();
        addMessage("user", text);
        addSystem(thinkingName + "正在思考。如果超过 " + Math.round(WEB_TIMEOUT_MS / 1000) + " 秒，会自动解锁。");
        const data = await post("/api/chat", { session_id: currentSessionId, text, character_id: sendingCharacterId });
        lastDebugTrace = data.debug_trace || null;
        renderDevPanel(lastDebugTrace);
        const routeSummary = routePlanSummary(data.route_plan);
        if (replyMode === "auto" && routeSummary) {
          addSystem(routeSummary);
        } else if (replyMode === "auto" && data.character?.name) {
          addSystem("自动形态选择：" + data.character.name);
        }
        if (data.character?.id) {
          activeCharacterId = data.character.id;
          localStorage.setItem("xiaolu.character", activeCharacterId);
          updateAnimalState(data.character.id, data.reply);
          renderSelectedAnimalCard();
        }
        if (Array.isArray(data.group_messages) && data.group_messages.length) {
          const knowledgeCards = Array.isArray(data.knowledge_cards) ? data.knowledge_cards : [];
          const mainMessageIndex = data.group_messages.findIndex(item => String(item.role || item.group_role || "").trim().toLowerCase() === "main");
          const cardTargetIndex = mainMessageIndex >= 0 ? mainMessageIndex : data.group_messages.length - 1;
          data.group_messages.forEach((item, index) => {
            if (item.character?.id) updateAnimalState(item.character.id, item.text);
            addMessage(
              "deer",
              item.text,
              index === cardTargetIndex ? knowledgeCards : [],
              item.character?.id || activeCharacterId,
              { groupRole: item.role, action: item.action || "", expressionId: item.expression?.id || item.expression_id || "" }
            );
          });
        } else {
          addMessage("deer", data.reply, data.knowledge_cards || [], data.character?.id || activeCharacterId, { expressionId: data.expression?.id || "" });
        }
      } catch (error) {
        addSystem(error.message);
      } finally {
        setBusy(false);
        input.focus();
      }
    });

    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        form.requestSubmit();
      }
    });

    end.addEventListener("click", async () => {
      if (busy) return;
      if (!sessionId) {
        addSystem("还没有可总结的会话。先发送一条消息，再结束并总结。");
        input.focus();
        return;
      }
      setBusy(true);
      try {
        addSystem("正在结束并总结。这一步会写 journal、合并记忆、更新长期状态，可能需要 " + Math.round(END_TIMEOUT_MS / 1000) + " 秒以内。");
        const data = await post("/api/end", { session_id: sessionId }, END_TIMEOUT_MS);
        addSystem((data.reused ? "已读取已有会话总结：" : "会话总结：") + "\\n" + data.journal.summary);
        const memoryEvents = data.memory_events || data.memories || [];
        if (memoryEvents.length) {
          addSystem("记忆处理：\\n" + memoryEvents.map(m => "- " + (m.action || "create") + " [" + m.category + "/" + (m.subcategory || "general") + "] " + m.content).join("\\n"));
        } else {
          addSystem("这次没有新增长期记忆。");
        }
        if ((data.state_profiles || []).length) {
          addSystem("长期状态画像：\\n" + data.state_profiles.map(p => "- " + (p.action || "update") + " [" + p.domain + "] " + p.stage).join("\\n"));
        } else {
          addSystem("这次没有更新长期状态画像。");
        }
        await loadData(activeDataView);
        sessionId = null;
      } catch (error) {
        addSystem(error.message);
      } finally {
        setBusy(false);
        input.focus();
      }
    });

    function switchMainView(view) {
      const showData = view === "data";
      dashboard.classList.toggle("hidden", !showData);
      messages.classList.toggle("hidden", showData);
      controlsPanel.classList.remove("hidden");
      animalPanel.classList.toggle("hidden", showData);
      form.classList.toggle("hidden", showData);
      chatTab.classList.toggle("active", !showData);
      dataTab.classList.toggle("active", showData);
      if (showData) loadData(activeDataView);
    }

    function escapeHtml(value) {
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;");
    }

    function shortId(id) {
      return String(id || "").slice(0, 8);
    }

    function speakerName(message) {
      if (message.role === "user") return "你";
      return characterById(message.character_id).name;
    }

    function renderList(items, renderer) {
      if (!items.length) {
        dataList.className = "";
        dataList.innerHTML = '<div class="empty">还没有保存的数据。</div>';
        return;
      }
      dataList.className = "grid";
      dataList.innerHTML = items.map(renderer).join("");
    }

    function renderSessions(items) {
      renderList(items, item => `
        <article class="card">
          <h3>Session ${escapeHtml(shortId(item.id))}</h3>
          <div class="meta">id: ${escapeHtml(item.id)}</div>
          <div class="meta">created: ${escapeHtml(item.created_at)}</div>
          <div class="meta">ended: ${escapeHtml(item.ended_at || "未结束")}</div>
          <div class="content">
            <span class="pill">${item.message_count} messages</span>
            <span class="pill">${item.journal_count} journals</span>
          </div>
          <button type="button" onclick="window.loadSession('${escapeHtml(item.id)}')">查看详情</button>
          <button type="button" onclick="window.loadSessionJournals('${escapeHtml(item.id)}')">查看总结日记</button>
          <button type="button" onclick="window.continueSession('${escapeHtml(item.id)}')">继续对话</button>
        </article>
      `);
    }

    function renderMemories(items) {
      memoryItems = items;
      if (memoryViewMode === "recent") {
        renderMemoryRecent();
      } else {
        renderMemoryTaxonomy();
      }
    }

    function renderMemorySwitch(activeMode) {
      return `
        <div class="memory-switch" aria-label="记忆查看方式">
          <button class="${activeMode === "taxonomy" ? "active" : ""}" type="button" onclick="window.setMemoryViewMode('taxonomy')">按分类</button>
          <button class="${activeMode === "recent" ? "active" : ""}" type="button" onclick="window.setMemoryViewMode('recent')">最近更新</button>
        </div>
      `;
    }

    window.setMemoryViewMode = function(mode) {
      memoryViewMode = mode === "recent" ? "recent" : "taxonomy";
      if (memoryViewMode === "recent") renderMemoryRecent();
      else renderMemoryTaxonomy();
    }

    function memoryDateLabel(item) {
      const updated = item.updated_at || "";
      const created = item.created_at || "";
      if (!updated && !created) return "无日期";
      if (updated && created && updated !== created) return "更新 " + updated + " · 创建 " + created;
      return "创建 " + (updated || created);
    }

    function renderMemoryCard(item) {
      const keywords = item.keywords || [];
      const status = item.status || "active";
      return `
        <article class="card">
          <h3>记忆 ${escapeHtml(shortId(item.id))}</h3>
          <div class="meta">category: ${escapeHtml(item.category || "uncategorized")} / ${escapeHtml(item.subcategory || "general")}</div>
          <div class="meta">status: ${escapeHtml(status)} · importance: ${escapeHtml(item.importance ?? "-")} · confidence: ${escapeHtml(item.confidence ?? "-")}</div>
          <div class="meta">${escapeHtml(memoryDateLabel(item))}</div>
          <div class="meta">source session: ${escapeHtml(shortId(item.source_session_id))}</div>
          ${item.merged_into_id ? `<div class="meta">merged into: ${escapeHtml(shortId(item.merged_into_id))}</div>` : ""}
          <div class="content"><b>内容</b>\n${escapeHtml(item.content || "无内容")}</div>
          <div class="content"><b>关键词</b><br>${keywords.length ? keywords.map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("") : '<span class="meta">无关键词</span>'}</div>
          <div class="content"><b>证据</b>\n${escapeHtml(item.evidence || "无证据")}</div>
          ${item.merge_note ? `<div class="content"><b>合并记录</b>\n${escapeHtml(item.merge_note)}</div>` : ""}
          <button type="button" onclick="window.loadSession('${escapeHtml(item.source_session_id)}')">查看来源 Session</button>
        </article>
      `;
    }

    function renderMemoryEventCard(item) {
      return `
        <article class="card">
          <h3>${escapeHtml(item.action || "memory")} · ${escapeHtml(item.category || "uncategorized")} / ${escapeHtml(item.subcategory || "general")}</h3>
          <div class="meta">created: ${escapeHtml(item.created_at || "")}</div>
          <div class="meta">memory id: ${escapeHtml(shortId(item.memory_id || ""))}</div>
          <div class="content"><b>内容</b>\n${escapeHtml(item.content || "无内容")}</div>
          ${item.reason ? `<div class="content"><b>处理原因</b>\n${escapeHtml(item.reason)}</div>` : ""}
        </article>
      `;
    }


    async function renderMemoryTaxonomy() {
      const taxonomy = await get("/api/memory_taxonomy");
      const groups = new Map();
      for (const item of taxonomy.items) {
        const key = item.category;
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(item);
      }
      dataList.className = "stack";
      dataList.innerHTML = renderMemorySwitch("taxonomy") + [...groups.entries()].map(([category, subcategories]) => `
        <section>
          <h2 class="group-title">${escapeHtml(category)} · ${subcategories.reduce((sum, item) => sum + item.count, 0)}</h2>
          <div class="grid">
            ${subcategories.map(item => `
              <article class="card clickable" onclick="window.showMemorySubcategory('${escapeHtml(item.category)}', '${escapeHtml(item.subcategory)}')">
                <h3>${escapeHtml(item.subcategory)}</h3>
                <div class="count">${item.count}</div>
                <div class="meta">active: ${item.active_count}</div>
                <div class="meta">category: ${escapeHtml(item.category)}</div>
              </article>
            `).join("")}
          </div>
        </section>
      `).join("");
    }

    function renderMemoryRecent() {
      const sorted = [...memoryItems].sort((left, right) => {
        const leftDate = left.updated_at || left.created_at || "";
        const rightDate = right.updated_at || right.created_at || "";
        return rightDate.localeCompare(leftDate);
      });
      dataList.className = "stack";
      dataList.innerHTML = `
        ${renderMemorySwitch("recent")}
        <section>
          <h2 class="group-title">最近更新 · ${sorted.length}</h2>
          <div class="meta">按 updated_at 从最近到最远排列；如果记忆刚创建，updated_at 和 created_at 通常相同。</div>
          <div class="grid">
            ${sorted.length ? sorted.map(renderMemoryCard).join("") : '<div class="empty">还没有保存的记忆。</div>'}
          </div>
        </section>
      `;
    }

    window.showMemorySubcategory = function(category, subcategory) {
      const memories = memoryItems.filter(item =>
        item.category === category && (item.subcategory || "general") === subcategory
      );
      dataList.className = "stack";
      dataList.innerHTML = `
        <section>
          <h2 class="group-title">${escapeHtml(category)} / ${escapeHtml(subcategory)} · ${memories.length}</h2>
          <button type="button" onclick="window.setMemoryViewMode('taxonomy')">返回小类总览</button>
          <div class="grid">
            ${memories.length ? memories.map(renderMemoryCard).join("") : '<div class="empty">这个小类目前还没有记忆。</div>'}
          </div>
        </section>
      `;
    }

    function renderJournals(items) {
      dataList.className = "grid";
      dataList.innerHTML = items.length
        ? items.map(item => renderJournalCard(item, { showSessionButton: true })).join("")
        : '<div class="empty">还没有总结日记。</div>';
    }

    function renderJournalCard(item, options = {}) {
      const emotionCurve = item.emotion_curve || [];
      const keywords = item.keywords || [];
      const insights = item.insights || [];
      return `
        <article class="card">
          <h3>总结日记 ${escapeHtml(shortId(item.session_id))}</h3>
          <div class="meta">session: ${escapeHtml(item.session_id)}</div>
          <div class="meta">created: ${escapeHtml(item.created_at || "-")}</div>
          <div class="meta">mood: ${escapeHtml(item.mood_score ?? "未标注")} · dominant emotion: ${escapeHtml(item.dominant_emotion || "未标注")}</div>
          <div class="content"><b>总结</b>\n${escapeHtml(item.summary || "无总结")}</div>
          <div class="content"><b>关键词</b><br>${keywords.length ? keywords.map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("") : '<span class="meta">无关键词</span>'}</div>
          <div class="content"><b>情绪曲线</b><br>${emotionCurve.length ? emotionCurve.map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("") : '<span class="meta">无情绪曲线</span>'}</div>
          <div class="content"><b>洞察</b>\n${insights.length ? insights.map(item => "- " + escapeHtml(item)).join("\\n") : "无"}</div>
          <div class="content"><b>下一步</b>\n${escapeHtml(item.suggested_next_step || "无")}</div>
          ${options.showSessionButton ? `<button type="button" onclick="window.loadSession('${escapeHtml(item.session_id)}')">查看关联 Session</button>` : ""}
        </article>
      `;
    }

    function trendLabel(trend) {
      const labels = {
        unknown: "未知",
        stable: "稳定",
        softening: "变柔和",
        intensifying: "增强",
        fluctuating: "波动",
        integrating: "整合中"
      };
      return labels[trend] || trend || "未知";
    }

    function stateDomainLabel(domain) {
      const labels = {
        self_relation: "自我关系",
        emotion_regulation: "情绪调节",
        relationship: "关系模式",
        agency_boundary: "行动与边界",
        trauma_pattern: "创伤阴影",
        meaning_value: "意义与价值"
      };
      return labels[domain] || domain || "未知领域";
    }

    function renderStateProfiles(items) {
      if (!items.length) {
        dataList.className = "";
        dataList.innerHTML = '<div class="empty">还没有长期状态画像。结束几次有内容的会话后，这里会形成跨时间的心理地图。</div>';
        return;
      }
      const completed = items.filter(row => Boolean(row.current)).length;
      dataList.className = "stack";
      dataList.innerHTML = `
        <section class="state-overview">
          <div>
            <h2>长期心理地图</h2>
            <div class="meta">六个领域会在每次会话结束后共同接受审阅。资料不足的领域保持空白，不会为了完整度而猜测。</div>
          </div>
          <div class="state-coverage">
            <strong>${completed} / ${items.length}</strong>
            <span class="meta">已形成画像</span>
          </div>
        </section>
        <section class="state-map">
          ${items.map(row => {
            const item = row.current;
            const history = row.history || [];
            return `
              <details class="state-domain ${item ? "" : "empty-state"}">
                <summary>
                  <span class="state-domain-title">
                    <strong>${escapeHtml(stateDomainLabel(row.domain))}</strong>
                    <span class="state-status">${item ? "已形成" : "待形成"}</span>
                  </span>
                  <span class="state-glance">
                    <span class="state-stage">${escapeHtml(item?.stage || "尚未形成清晰阶段")}</span>
                    <span class="state-preview">${escapeHtml(item?.summary || "目前没有足够的跨会话证据，后续对话触及这一领域时会逐步补全。")}</span>
                  </span>
                  <span class="state-metrics">${item ? `${escapeHtml(trendLabel(item.trend))} · ${escapeHtml(item.intensity)}/10` : "资料不足"}</span>
                </summary>
                <div class="state-domain-detail">
                  ${item ? `
                    <div class="state-summary">${escapeHtml(item.summary || "暂无综合摘要")}</div>
                    <div class="state-strategy"><b>陪伴方向</b><br>${escapeHtml(item.support_strategy || "暂无")}</div>
                    ${(item.evidence || []).length ? `
                      <div class="state-evidence">
                        ${(item.evidence || []).map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("")}
                      </div>
                    ` : ""}
                    <div class="meta">置信度 ${escapeHtml(item.confidence)} · 更新于 ${escapeHtml(item.updated_at || "")}</div>
                    <button type="button" onclick="window.loadSession('${escapeHtml(item.source_session_id)}')">查看最近来源</button>
                  ` : '<div class="meta">这一领域暂时保持空白，不会根据有限信息推断长期结论。</div>'}
                  <details class="state-history">
                    <summary>变化记录（${history.length}）</summary>
                    ${history.length ? history.map(version => `
                      <div class="state-version">
                        <div class="meta">${escapeHtml(version.created_at || "")} · ${escapeHtml(trendLabel(version.trend))} · 强度 ${escapeHtml(version.intensity)}/10</div>
                        <div class="state-version-title">${escapeHtml(version.stage || "未命名阶段")}</div>
                        <div>${escapeHtml(version.summary || "")}</div>
                        <div class="meta">更新原因：${escapeHtml(version.reason || "无")}</div>
                        <button type="button" onclick="window.loadSession('${escapeHtml(version.source_session_id)}')">查看来源</button>
                      </div>
                    `).join("") : '<div class="meta">暂无历史版本。</div>'}
                  </details>
                </div>
              </details>
            `;
          }).join("")}
        </section>
      `;
    }

    function renderKnowledge(items) {
      renderList(items, item => `
        <article class="card clickable" onclick="showKnowledgeDetail('${escapeHtml(item.id)}')">
          <h3>${escapeHtml(item.title)}</h3>
          <div class="meta">domain: ${escapeHtml(item.domain)} · source: ${escapeHtml(item.source)}</div>
          <div>${(item.tags || []).map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("")}</div>
          <div class="content">${escapeHtml(item.concept)}</div>
          <div class="meta">适用：${escapeHtml(item.use_when)}</div>
          <div class="meta">小鹿表达：${escapeHtml(item.xiaolu_style)}</div>
          <div class="content">回应提示：${escapeHtml(item.response_hint)}</div>
        </article>
      `);
    }

    function renderContentLibrary(items) {
      const types = ["book", "practice", "music", "film"];
      const grouped = new Map(types.map(type => [type, []]));
      for (const item of items) {
        if (!grouped.has(item.type)) grouped.set(item.type, []);
        grouped.get(item.type).push(item);
      }
      dataList.className = "stack";
      dataList.innerHTML = `
        <section class="hero-card">
          <h2 class="group-title">Content Library</h2>
          <div class="meta">小鹿可以引用的内容素材库：书籍、练习、音乐和电影。当前是 demo 级素材，后续可以继续扩展来源、评分和个性化推荐。</div>
        </section>
        ${[...grouped.entries()].map(([type, cards]) => `
          <section>
            <h2 class="group-title">${escapeHtml(type)} · ${cards.length}</h2>
            <div class="grid">
              ${cards.map(item => `
                <article class="card">
                  <div class="content-type">${escapeHtml(item.type)}</div>
                  <h3>${escapeHtml(item.title)}</h3>
                  <div class="meta">${escapeHtml(item.creator)}</div>
                  <div>${(item.tags || []).map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("")}</div>
                  <div class="content">${escapeHtml(item.fit_for)}</div>
                  <div class="meta">小鹿用法：${escapeHtml(item.xiaolu_note)}</div>
                  <div class="meta">来源：${escapeHtml(item.source_label)}</div>
                  ${item.source_url ? `<a href="${escapeHtml(item.source_url)}" target="_blank" rel="noreferrer">打开来源</a>` : ""}
                </article>
              `).join("")}
            </div>
          </section>
        `).join("")}
      `;
    }

    function moodLabel(score) {
      if (score > 0.5) return "偏积极";
      if (score < -0.5) return "偏低落";
      return "中性/混合";
    }

    function moodClass(score) {
      if (score > 0.5) return "positive";
      if (score < -0.5) return "negative";
      return "neutral";
    }

    function dayClass(score) {
      if (score > 0.5) return "good";
      if (score < -0.5) return "bad";
      return "neutral";
    }

    function renderMood(data) {
      const daily = data.daily || [];
      const weekly = data.weekly || [];
      if (!daily.length) {
        dataList.className = "";
        dataList.innerHTML = '<div class="empty">还没有 journal，结束几次会话后这里会出现心情轨迹。</div>';
        return;
      }
      const bars = daily.slice(-21).map(day => {
        const height = Math.max(12, Math.round((Math.abs(day.score) / 3) * 140));
        return `<div class="bar ${moodClass(day.score)}" style="height:${height}px" title="${escapeHtml(day.date)} · ${day.score}"></div>`;
      }).join("");
      const calendar = daily.slice(-35).map(day => `
        <article class="day ${dayClass(day.score)}">
          <div class="meta">${escapeHtml(day.date)}</div>
          <h3>${moodLabel(day.score)}</h3>
          <div class="meta">score: ${day.score} · ${escapeHtml(day.dominant_emotion || "未标注")} · ${day.count} journals</div>
          <div>${(day.keywords || []).map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("")}</div>
        </article>
      `).join("");
      const weekCards = weekly.slice(0, 6).map(week => `
        <article class="card">
          <h3>${escapeHtml(week.week)} · ${moodLabel(week.score)}</h3>
          <div class="meta">avg score: ${week.score} · ${escapeHtml(week.dominant_emotion || "未标注")} · ${week.count} journals</div>
          <div>${(week.keywords || []).map(k => `<span class="pill">${escapeHtml(k)}</span>`).join("")}</div>
          <div class="content">${escapeHtml(week.summary)}</div>
        </article>
      `).join("");
      dataList.className = "stack";
      dataList.innerHTML = `
        <section class="chart">
          <h2 class="group-title">最近心情轨迹</h2>
          <div class="meta">绿色偏积极，红色偏低落，灰色表示中性或混合。当前是基于 journal 关键词和摘要的启发式估计。</div>
          <div class="bars">${bars}</div>
        </section>
        <section>
          <h2 class="group-title">日历视图</h2>
          <div class="calendar">${calendar}</div>
        </section>
        <section>
          <h2 class="group-title">周报原型</h2>
          <div class="grid">${weekCards}</div>
        </section>
      `;
    }

    function renderMessages(items) {
      renderList(items, item => `
        <article class="card">
          <h3>${escapeHtml(speakerName(item))}</h3>
          <div class="meta">session: ${escapeHtml(shortId(item.session_id))} · ${escapeHtml(item.created_at)}</div>
          <div class="meta">model: ${escapeHtml(item.model || "-")}</div>
          <div class="content">${escapeHtml(item.content)}</div>
        </article>
      `);
    }

    async function loadData(view) {
      activeDataView = view;
      dataButtons.forEach(button => button.classList.toggle("active", button.dataset.view === view));
      dataList.className = "";
      dataList.innerHTML = '<div class="empty">加载中...</div>';
      try {
        if (view === "mood") {
          const mood = await get("/api/mood_analytics");
          renderMood(mood);
          return;
        }
        const data = await get("/api/data?type=" + encodeURIComponent(view));
        if (view === "sessions") renderSessions(data.items);
        if (view === "memories") renderMemories(data.items);
        if (view === "state") renderStateProfiles(data.items);
        if (view === "knowledge") renderKnowledge(data.items);
        if (view === "content") renderContentLibrary(data.items);
        if (view === "journals") renderJournals(data.items);
        if (view === "messages") renderMessages(data.items);
      } catch (error) {
        dataList.innerHTML = '<div class="empty">' + escapeHtml(error.message) + '</div>';
      }
    }

    window.loadSession = async function(sessionId) {
      dataButtons.forEach(button => button.classList.remove("active"));
      dataList.className = "";
      dataList.innerHTML = '<div class="empty">加载 session 详情...</div>';
      try {
        const data = await get("/api/session_detail?id=" + encodeURIComponent(sessionId));
        const messages = data.messages || [];
        const journals = data.journals || [];
        const memories = data.memories || [];
        const memoryEvents = data.memory_events || [];
        dataList.className = "stack";
        dataList.innerHTML = `
          <section>
            <h2 class="group-title">Session ${escapeHtml(shortId(sessionId))} 详情</h2>
            <div class="meta">${messages.length} messages · ${journals.length} journals · ${memoryEvents.length} memory events · ${memories.length} current memories</div>
          </section>
          <section>
            <h2 class="group-title">对话记录</h2>
            <div class="grid">
              <article class="card"><div class="content">${messages.map(m => `<b>${escapeHtml(speakerName(m))}</b>\\n${escapeHtml(m.content)}`).join("\\n\\n") || "无"}</div></article>
            </div>
          </section>
          <section>
            <h2 class="group-title">总结日记 · ${journals.length}</h2>
            <div class="grid">
              ${journals.length ? journals.map(item => renderJournalCard(item)).join("") : '<div class="empty">这个 Session 还没有总结日记。</div>'}
            </div>
          </section>
          <section>
            <h2 class="group-title">本 Session 记忆处理记录 · ${memoryEvents.length}</h2>
            <div class="grid">
              ${memoryEvents.length ? memoryEvents.map(renderMemoryEventCard).join("") : '<div class="empty">这个 Session 还没有记忆处理记录。旧数据可能只有当前关联记忆。</div>'}
            </div>
          </section>
          <section>
            <h2 class="group-title">当前关联记忆 · ${memories.length}</h2>
            <div class="grid">
              ${memories.length ? memories.map(renderMemoryCard).join("") : '<div class="empty">这个 Session 还没有关联记忆。</div>'}
            </div>
          </section>
        `;
      } catch (error) {
        dataList.innerHTML = '<div class="empty">' + escapeHtml(error.message) + '</div>';
      }
    }

    window.loadSessionJournals = async function(sessionId) {
      dataButtons.forEach(button => button.classList.remove("active"));
      dataList.className = "";
      dataList.innerHTML = '<div class="empty">加载总结日记...</div>';
      try {
        const data = await get("/api/session_detail?id=" + encodeURIComponent(sessionId));
        const journals = data.journals || [];
        const memories = data.memories || [];
        const memoryEvents = data.memory_events || [];
        dataList.className = "stack";
        dataList.innerHTML = `
          <section>
            <h2 class="group-title">Session ${escapeHtml(shortId(sessionId))} 的总结日记 · ${journals.length}</h2>
            <button type="button" onclick="window.loadSession('${escapeHtml(sessionId)}')">查看对话详情</button>
            <button type="button" onclick="loadData('sessions')">返回 Sessions</button>
            <div class="grid">
              ${journals.length ? journals.map(item => renderJournalCard(item)).join("") : '<div class="empty">这个 Session 还没有总结日记。结束并总结后会出现在这里。</div>'}
            </div>
          </section>
          <section>
            <h2 class="group-title">同一 Session 记忆处理记录 · ${memoryEvents.length}</h2>
            <div class="grid">
              ${memoryEvents.length ? memoryEvents.map(renderMemoryEventCard).join("") : '<div class="empty">这个 Session 还没有记忆处理记录。旧数据可能只有当前关联记忆。</div>'}
            </div>
          </section>
          <section>
            <h2 class="group-title">当前关联记忆 · ${memories.length}</h2>
            <div class="grid">
              ${memories.length ? memories.map(renderMemoryCard).join("") : '<div class="empty">这个 Session 还没有关联记忆。</div>'}
            </div>
          </section>
        `;
      } catch (error) {
        dataList.innerHTML = '<div class="empty">' + escapeHtml(error.message) + '</div>';
      }
    }

    window.continueSession = async function(targetSessionId) {
      if (busy) return;
      try {
        const data = await get("/api/session_detail?id=" + encodeURIComponent(targetSessionId));
        sessionId = targetSessionId;
        messages.innerHTML = "";
        for (const message of data.messages) {
          addMessage(
            message.role === "user" ? "user" : "deer",
            message.content,
            message.knowledge_cards || [],
            message.character_id || null,
            { groupRole: message.group_role || "", action: message.action || "", expressionId: message.expression_id || "" }
          );
        }
        switchMainView("chat");
      addSystem("已继续 Session " + shortId(targetSessionId) + "。新消息会追加到这个会话里。");
      renderAnimalStates(activeCharacterId);
      input.focus();
      } catch (error) {
        dataList.innerHTML = '<div class="empty">' + escapeHtml(error.message) + '</div>';
      }
    }

    chatTab.addEventListener("click", () => switchMainView("chat"));
    dataTab.addEventListener("click", () => switchMainView("data"));
    moodShortcut.addEventListener("click", () => {
      activeDataView = "mood";
      switchMainView("data");
    });
    journalShortcut.addEventListener("click", () => {
      activeDataView = "journals";
      switchMainView("data");
    });
    stateShortcut.addEventListener("click", () => {
      activeDataView = "state";
      switchMainView("data");
    });
    chatShortcut.addEventListener("click", () => switchMainView("chat"));
    devPanelToggle.addEventListener("click", () => {
      renderDevPanel(lastDebugTrace);
      devPanel.classList.toggle("hidden");
    });
    groupToggle.addEventListener("click", () => {
      setReplyMode(replyMode === "auto" ? "manual" : "auto");
    });
    refreshData.addEventListener("click", () => loadData(activeDataView));
    cleanupSessions.addEventListener("click", async () => {
      try {
        const data = await post("/api/cleanup_empty_sessions", {});
        dataList.innerHTML = '<div class="empty">已清理 ' + data.deleted + ' 个空 session。</div>';
        await loadData("sessions");
      } catch (error) {
        dataList.innerHTML = '<div class="empty">' + escapeHtml(error.message) + '</div>';
      }
    });
    dataButtons.forEach(button => button.addEventListener("click", () => loadData(button.dataset.view)));

    updateCharacterBrand();
    setReplyMode(replyMode);
    renderAnimalStates(activeCharacterId);
    addSystem("新的会话会在你发送第一条消息时保存。");
  </script>
</body>
</html>
"""


class WebApp:
    def __init__(self) -> None:
        self.orchestrator = build_orchestrator()


class WebServer(ThreadingHTTPServer):
    logger = logging.getLogger(__name__)

    def handle_error(self, request, client_address) -> None:
        error = sys.exception()
        if isinstance(
            error,
            (BrokenPipeError, ConnectionAbortedError, ConnectionResetError),
        ):
            self.logger.debug(
                "client disconnected address=%r error=%s",
                client_address,
                type(error).__name__,
            )
            return
        super().handle_error(request, client_address)


class Handler(BaseHTTPRequestHandler):
    app: WebApp
    logger = logging.getLogger(__name__)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        started_at = time.monotonic()
        self.logger.info("http start path=%s", path)
        try:
            if path == "/api/session":
                session_id = self.app.orchestrator.start_session()
                self.respond_json({"session_id": session_id})
                return
            payload = self.read_json()
            if path == "/api/chat":
                result = self.app.orchestrator.reply_detail(
                    payload["session_id"],
                    payload["text"],
                    character_id=payload.get("character_id"),
                )
                self.respond_json(result)
                return
            if path == "/api/end":
                result = self.app.orchestrator.close_session(payload["session_id"])
                self.respond_json(result)
                return
            if path == "/api/home_hint_feedback":
                self.app.orchestrator.record_home_hint_feedback(
                    hint_id=payload["hint_id"],
                    text=payload["text"],
                    liked=bool(payload.get("liked")),
                    source=payload.get("source", ""),
                    context=payload.get("context") if isinstance(payload.get("context"), dict) else {},
                )
                self.respond_json({"ok": True})
                return
            if path == "/api/cleanup_empty_sessions":
                deleted = self.app.orchestrator.store.delete_empty_sessions()
                self.respond_json({"deleted": deleted})
                return
            if path == "/api/sync/merge":
                settings = get_settings()
                supplied_token = self.headers.get("X-Sensen-Sync-Token", "")
                if not settings.sync_token:
                    self.respond_json({"error": "sync is not configured on this Mac"}, status=503)
                    return
                if not secrets.compare_digest(supplied_token, settings.sync_token):
                    self.respond_json({"error": "invalid sync token"}, status=401)
                    return
                result = self.app.orchestrator.store.merge_sync_bundle(payload)
                self.respond_json({"ok": True, "merged": result})
                return
            self.send_error(404)
        except Exception as error:
            self.logger.exception("http error path=%s", path)
            self.respond_json({"error": str(error)}, status=500)
        finally:
            self.logger.info(
                "http done path=%s elapsed=%.2fs",
                path,
                time.monotonic() - started_at,
            )

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8")
        return json.loads(body or "{}")

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/":
            settings = get_settings()
            html = (
                HTML
                .replace("__WEB_TIMEOUT_MS__", str(settings.web_timeout_ms))
                .replace("__CHARACTERS_JSON__", json.dumps(list_characters(), ensure_ascii=False))
            )
            self.respond_html(html)
            return
        if path.startswith("/static/"):
            self.respond_static(path.removeprefix("/static/"))
            return
        try:
            if path == "/api/health":
                self.respond_json({"ok": True})
                return
            if path == "/api/data":
                self.respond_data()
                return
            if path == "/api/session_detail":
                self.respond_session_detail()
                return
            if path == "/api/memory_taxonomy":
                self.respond_json({"items": self.app.orchestrator.store.memory_taxonomy_counts()})
                return
            if path == "/api/mood_analytics":
                self.respond_json(self.app.orchestrator.store.journal_analytics())
                return
            if path == "/api/home_hint":
                self.respond_home_hint()
                return
            if path == "/api/star_map_insight":
                self.respond_star_map_insight()
                return
            if path == "/api/knowledge_detail":
                self.respond_knowledge_detail()
                return
            self.send_error(404)
        except Exception as error:
            self.logger.exception("http get error path=%s", path)
            self.respond_json({"error": str(error)}, status=500)

    def respond_data(self) -> None:
        query = urlparse(self.path).query
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        data_type = params.get("type", "sessions")
        store = self.app.orchestrator.store
        requested_limit = None
        if "limit" in params:
            try:
                requested_limit = max(1, min(int(params["limit"]), 2000))
            except (TypeError, ValueError):
                self.respond_json({"error": "limit must be an integer"}, status=400)
                return
        if data_type == "sessions":
            items = store.list_sessions(limit=requested_limit or 50)
        elif data_type == "memories":
            items = store.list_memories(limit=requested_limit or 200)
        elif data_type == "state":
            items = store.state_profile_overview()
        elif data_type == "journals":
            items = store.list_journals(limit=requested_limit or 100)
        elif data_type == "messages":
            items = store.list_messages(limit=requested_limit or 200)
        elif data_type == "knowledge":
            items = self.app.orchestrator.knowledge.list_cards()
        elif data_type == "content":
            items = self.app.orchestrator.knowledge.list_content_cards()
        else:
            self.respond_json({"error": f"unknown data type: {data_type}"}, status=400)
            return
        self.respond_json({"items": items})

    def respond_home_hint(self) -> None:
        self.respond_json(self.app.orchestrator.generate_home_hint())

    def respond_star_map_insight(self) -> None:
        self.respond_json(self.app.orchestrator.generate_star_map_insight())

    def respond_knowledge_detail(self) -> None:
        query = urlparse(self.path).query
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        card_id = params.get("id")
        if not card_id:
            self.respond_json({"error": "missing knowledge card id"}, status=400)
            return
        card = self.app.orchestrator.knowledge.get_card(card_id)
        if not card:
            self.respond_json({"error": f"unknown knowledge card: {card_id}"}, status=404)
            return
        self.respond_json(
            {
                "card": card,
                "related_content": self.app.orchestrator.knowledge.related_content_for_knowledge(card_id),
            }
        )

    def respond_session_detail(self) -> None:
        query = urlparse(self.path).query
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        session_id = params.get("id")
        if not session_id:
            self.respond_json({"error": "missing session id"}, status=400)
            return
        store = self.app.orchestrator.store
        messages = store.list_messages(session_id=session_id)
        for message in messages:
            card_ids = message.get("knowledge_card_ids", [])
            message["knowledge_cards"] = [
                card
                for card_id in card_ids
                if (card := self.app.orchestrator.knowledge.get_card(card_id))
            ]
        self.respond_json(
            {
                "messages": messages,
                "journals": store.list_journals(session_id=session_id),
                "memories": store.list_memories(session_id=session_id),
                "memory_events": store.list_memory_events(session_id=session_id),
            }
        )

    def respond_html(self, html: str) -> None:
        data = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def respond_static(self, name: str) -> None:
        if "/" in name or "\\" in name:
            self.send_error(404)
            return
        path = STATIC_DIR / name
        if not path.exists() or not path.is_file():
            self.send_error(404)
            return
        content_types = {
            ".png": "image/png",
            ".webp": "image/webp",
        }
        content_type = content_types.get(path.suffix, "application/octet-stream")
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "public, max-age=86400")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def respond_json(self, payload: dict, status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args) -> None:
        return


def main() -> None:
    settings = get_settings()
    Handler.app = WebApp()
    server = WebServer((settings.web_host, settings.web_port), Handler)
    local_url = f"http://127.0.0.1:{settings.web_port}"
    bound_url = f"http://{settings.web_host}:{settings.web_port}"
    print(f"小鹿 Web UI 已启动：{local_url}")
    if settings.web_host in {"0.0.0.0", ""}:
        print(f"局域网访问：在手机浏览器打开 http://{get_lan_ip()}:{settings.web_port}")
    elif settings.web_host != "127.0.0.1":
        print(f"绑定地址：{bound_url}")
    print(f"后台日志：{settings.log_path}")
    print("按 Ctrl+C 停止。")
    server.serve_forever()


def get_lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
    except OSError:
        return "你的Mac局域网IP"


if __name__ == "__main__":
    main()
