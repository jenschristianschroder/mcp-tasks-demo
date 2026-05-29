export interface EasyAuthUser {
  name: string;
  id: string;
  accessToken: string | null;
}

interface AuthMeClaim {
  typ: string;
  val: string;
}

interface AuthMeEntry {
  access_token: string;
  id_token: string;
  user_claims: AuthMeClaim[];
  user_id: string;
}

let cachedUser: EasyAuthUser | null = null;

export async function getAuthUser(): Promise<EasyAuthUser | null> {
  if (cachedUser) return cachedUser;

  try {
    const response = await fetch('/.auth/me');
    if (!response.ok) return null;

    const data: AuthMeEntry[] = await response.json();
    if (!data || data.length === 0) return null;

    const entry = data[0];
    const nameClaim = entry.user_claims?.find(
      (c) => c.typ === 'name' || c.typ === 'preferred_username'
    );

    cachedUser = {
      name: nameClaim?.val || entry.user_id || '',
      id: entry.user_id,
      accessToken: entry.access_token || null,
    };
    return cachedUser;
  } catch {
    return null;
  }
}

export async function getAccessToken(): Promise<string | null> {
  const user = await getAuthUser();
  return user?.accessToken ?? null;
}

export function login() {
  window.location.href = '/.auth/login/aad?post_login_redirect_uri=' + encodeURIComponent(window.location.pathname);
}

export function logout() {
  cachedUser = null;
  window.location.href = '/.auth/logout';
}

export function clearCache() {
  cachedUser = null;
}
