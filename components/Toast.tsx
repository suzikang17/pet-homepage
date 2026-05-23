type ToastProps = {
  message: string;
  show: boolean;
};

export function Toast({ message, show }: ToastProps) {
  return (
    <div className={`toast ${show ? "show" : ""}`} role="status" aria-live="polite">
      <span className="dot"></span>
      <span>{message}</span>
    </div>
  );
}
