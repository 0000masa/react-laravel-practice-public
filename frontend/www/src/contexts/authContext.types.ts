import { createContext } from 'react';

// ユーザー情報の型定義
export interface User {
  id: number;
  name: string;
  email: string;
  avatar_url: string | null;
}

// 認証コンテキストの型定義
export interface AuthContextType {
  user: User | null;
  isLoading: boolean;
  login: (user: User) => void;
  logout: () => Promise<void>;
  checkAuth: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextType | undefined>(undefined);

