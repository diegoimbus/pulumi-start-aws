// Si no está definida (entorno Docker), usa /api y se apoya en el proxy para redirigir
const baseURL = import.meta.env.VITE_API_BASE_URL || "/api";

export const getTodos = async () => {
  return fetch(`${baseURL}/todos/`);
};
