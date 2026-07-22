import { useEffect, useState, type FormEvent } from "react";
import { friendlyError, type MusicApi } from "../api/client";
import type { AuthSessionResponse } from "../api/types";
import { Icon } from "./Icon";

interface AuthPageProps {
  api: MusicApi;
  mode: "register" | "login";
  onAuthenticated(session: AuthSessionResponse): void;
}

export function AuthPage({ api, mode, onAuthenticated }: AuthPageProps) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setPassword("");
    setConfirmPassword("");
    setError(null);
  }, [mode]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedUsername = username.trim();
    if (!normalizedUsername) {
      setError("请输入管理员账号");
      return;
    }
    if (!password) {
      setError("请输入密码");
      return;
    }
    if (mode === "register" && password.length < 12) {
      setError("密码至少需要 12 个字符");
      return;
    }
    if (mode === "register" && password !== confirmPassword) {
      setError("两次输入的密码不一致");
      return;
    }

    setSubmitting(true);
    setError(null);
    try {
      const credentials = {
        username: normalizedUsername,
        password,
      };
      const session = registering
        ? await api.register(credentials).then(() => api.login(credentials))
        : await api.login(credentials);
      onAuthenticated(session);
    } catch (submitError) {
      setError(friendlyError(submitError));
    } finally {
      setSubmitting(false);
    }
  }

  const registering = mode === "register";

  return (
    <main className="auth-shell">
      <section className="auth-card" aria-labelledby="auth-title">
        <div className="auth-brand">
          <div className="brand__mark" aria-hidden="true">
            <img alt="" src="/brand/lyranest-logo-512.png" />
          </div>
          <div>
            <strong>LyraNest Community</strong>
            <small>律巢社区版</small>
          </div>
        </div>

        <div className="auth-copy">
          <span className="eyebrow">
            {registering ? "首次初始化" : "管理员登录"}
          </span>
          <h1 id="auth-title">
            {registering ? "创建管理员账号" : "欢迎回来"}
          </h1>
          <p>
            {registering
              ? "这是首次启动。请创建管理员账号，完成后即可管理和播放你的音乐。"
              : "请输入管理员账号和密码以进入音乐库。"}
          </p>
        </div>

        <form className="auth-form" onSubmit={submit}>
          <label className="field">
            <span>管理员账号</span>
            <div className="field__input">
              <Icon name="manage" size={18} />
              <input
                autoComplete="username"
                autoFocus
                disabled={submitting}
                onChange={(event) => setUsername(event.target.value)}
                placeholder="请输入管理员账号"
                value={username}
              />
            </div>
          </label>

          <label className="field">
            <span>密码</span>
            <div className="field__input">
              <Icon name="library" size={18} />
              <input
                autoComplete={registering ? "new-password" : "current-password"}
                disabled={submitting}
                onChange={(event) => setPassword(event.target.value)}
                placeholder="请输入密码"
                type="password"
                value={password}
              />
            </div>
          </label>

          {registering && (
            <label className="field">
              <span>确认密码</span>
              <div className="field__input">
                <Icon name="check" size={18} />
                <input
                  autoComplete="new-password"
                  disabled={submitting}
                  onChange={(event) => setConfirmPassword(event.target.value)}
                  placeholder="请再次输入密码"
                  type="password"
                  value={confirmPassword}
                />
              </div>
            </label>
          )}

          {error && (
            <div className="auth-error" role="alert">
              <Icon name="alert" size={18} />
              <span>{error}</span>
            </div>
          )}

          <button
            className="button button--primary auth-submit"
            disabled={submitting}
            type="submit"
          >
            {submitting ? (
              <span className="spinner spinner--light" />
            ) : (
              <Icon name={registering ? "check" : "chevron"} size={18} />
            )}
            {submitting
              ? registering
                ? "正在创建…"
                : "正在登录…"
              : registering
                ? "创建账号并进入"
                : "登录"}
          </button>
        </form>
      </section>
    </main>
  );
}
