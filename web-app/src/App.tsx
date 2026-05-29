import { useState, useEffect, useCallback } from 'react';
import {
  makeStyles,
  tokens,
  Title1,
  Divider,
  Button,
  Body1,
  Persona,
} from '@fluentui/react-components';
import { SignOut24Regular } from '@fluentui/react-icons';
import { TaskList } from './components/TaskList';
import { TaskForm } from './components/TaskForm';
import { ApiConsole } from './components/ApiConsole';
import { tasksApi, onApiLog, setAccessTokenProvider } from './api/tasksApi';
import { getAuthUser, getAccessToken, login, logout, EasyAuthUser } from './auth/easyAuth';
import { ApiLogEntry, TodoTask } from './types';

const useStyles = makeStyles({
  root: {
    display: 'flex',
    flexDirection: 'column',
    height: '100vh',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: '16px 24px',
    backgroundColor: tokens.colorBrandBackground,
    color: tokens.colorNeutralForegroundOnBrand,
  },
  headerActions: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  },
  content: {
    display: 'flex',
    flex: 1,
    overflow: 'hidden',
  },
  mainPanel: {
    flex: 1,
    padding: '24px',
    overflowY: 'auto',
  },
  consolePanel: {
    width: '420px',
    borderLeft: `1px solid ${tokens.colorNeutralStroke1}`,
    display: 'flex',
    flexDirection: 'column',
  },
  loginContainer: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    gap: '16px',
  },
});

export default function App() {
  const styles = useStyles();
  const [user, setUser] = useState<EasyAuthUser | null>(null);
  const [tasks, setTasks] = useState<TodoTask[]>([]);
  const [logs, setLogs] = useState<ApiLogEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [authChecked, setAuthChecked] = useState(false);

  const isAuthenticated = !!user;

  // Fetch auth info from EasyAuth on mount.
  // With RedirectToLoginPage, the user is always authenticated by the time the SPA loads.
  // If /.auth/me fails (stale session), redirect back to login.
  useEffect(() => {
    getAuthUser().then((u) => {
      if (u) {
        setUser(u);
        setAuthChecked(true);
        setAccessTokenProvider(() => getAccessToken().then((t) => t || ''));
      } else {
        // Session is stale or missing — redirect to EasyAuth login
        login();
      }
    });
  }, []);

  useEffect(() => {
    const unsubscribe = onApiLog((entry) => {
      setLogs((prev) => [entry, ...prev]);
    });
    return unsubscribe;
  }, []);

  const loadTasks = useCallback(async () => {
    if (!isAuthenticated) return;
    setLoading(true);
    try {
      const data = await tasksApi.list();
      setTasks(data);
    } catch {
      // error shown in console
    } finally {
      setLoading(false);
    }
  }, [isAuthenticated]);

  useEffect(() => {
    loadTasks();
  }, [loadTasks]);

  const handleLogout = () => {
    logout();
  };

  const userName = user?.name || '';

  if (!authChecked) return null;

  return (
    <div className={styles.root}>
      <div className={styles.header}>
        <Title1 style={{ color: 'inherit' }}>Tasks Manager</Title1>
        <div className={styles.headerActions}>
          {isAuthenticated && (
            <>
              <Persona
                name={userName}
                size="small"
                primaryText={{ style: { color: 'inherit' } }}
              />
              <Button
                appearance="transparent"
                icon={<SignOut24Regular />}
                onClick={handleLogout}
                style={{ color: 'inherit' }}
              >
                Sign out
              </Button>
            </>
          )}
        </div>
      </div>
      <div className={styles.content}>
        {isAuthenticated ? (
          <>
            <div className={styles.mainPanel}>
              <TaskForm onCreated={loadTasks} />
              <Divider style={{ margin: '16px 0' }} />
              <TaskList tasks={tasks} loading={loading} onRefresh={loadTasks} />
            </div>
            <div className={styles.consolePanel}>
              <ApiConsole logs={logs} onClear={() => setLogs([])} />
            </div>
          </>
        ) : (
          <div className={styles.mainPanel}>
            <div className={styles.loginContainer}>
              <Body1>Loading authentication...</Body1>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
