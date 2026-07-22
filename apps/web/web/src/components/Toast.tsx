import { Icon } from "./Icon";

export interface ToastMessage {
  id: number;
  tone: "success" | "error" | "info";
  message: string;
}

interface ToastProps {
  toast: ToastMessage | null;
  onClose(): void;
}

export function Toast({ toast, onClose }: ToastProps) {
  if (!toast) {
    return null;
  }

  return (
    <div className={`toast toast--${toast.tone}`} role="status">
      <span className="toast__icon">
        <Icon name={toast.tone === "error" ? "alert" : "check"} size={18} />
      </span>
      <span>{toast.message}</span>
      <button aria-label="关闭提示" onClick={onClose} type="button">
        <Icon name="close" size={16} />
      </button>
    </div>
  );
}
