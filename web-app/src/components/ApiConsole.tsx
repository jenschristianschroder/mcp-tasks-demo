import {
  makeStyles,
  tokens,
  Body1,
  Caption1,
  Button,
  Badge,
  Subtitle2,
} from '@fluentui/react-components';
import { Delete24Regular } from '@fluentui/react-icons';
import { ApiLogEntry } from '../types';

const useStyles = makeStyles({
  root: {
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    overflow: 'hidden',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: '12px 16px',
    borderBottom: `1px solid ${tokens.colorNeutralStroke1}`,
    backgroundColor: tokens.colorNeutralBackground1,
  },
  logList: {
    flex: 1,
    overflowY: 'auto',
    padding: '8px',
  },
  logEntry: {
    padding: '10px 12px',
    marginBottom: '8px',
    borderRadius: tokens.borderRadiusMedium,
    backgroundColor: tokens.colorNeutralBackground1,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    fontFamily: 'Consolas, "Courier New", monospace',
    fontSize: '12px',
  },
  logHeader: {
    display: 'flex',
    gap: '8px',
    alignItems: 'center',
    marginBottom: '4px',
  },
  logMethod: {
    fontWeight: 700,
    minWidth: '50px',
  },
  logUrl: {
    flex: 1,
    wordBreak: 'break-all' as const,
  },
  logBody: {
    marginTop: '6px',
    padding: '8px',
    borderRadius: tokens.borderRadiusSmall,
    backgroundColor: tokens.colorNeutralBackground3,
    whiteSpace: 'pre-wrap' as const,
    wordBreak: 'break-all' as const,
    maxHeight: '200px',
    overflowY: 'auto',
  },
  logMeta: {
    display: 'flex',
    gap: '8px',
    alignItems: 'center',
    marginTop: '4px',
  },
  empty: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    height: '100%',
    color: tokens.colorNeutralForeground3,
  },
});

function getStatusColor(status: number): 'success' | 'warning' | 'danger' | 'informative' {
  if (status >= 200 && status < 300) return 'success';
  if (status >= 300 && status < 400) return 'warning';
  if (status >= 400) return 'danger';
  return 'informative';
}

const methodColors: Record<string, string> = {
  GET: tokens.colorPaletteBlueBackground2,
  POST: tokens.colorPaletteGreenBackground2,
  PUT: tokens.colorPaletteMarigoldBackground2,
  DELETE: tokens.colorPaletteRedBackground2,
};

interface ApiConsoleProps {
  logs: ApiLogEntry[];
  onClear: () => void;
}

export function ApiConsole({ logs, onClear }: ApiConsoleProps) {
  const styles = useStyles();

  return (
    <div className={styles.root}>
      <div className={styles.header}>
        <Subtitle2>API Console</Subtitle2>
        <Button
          appearance="subtle"
          icon={<Delete24Regular />}
          size="small"
          onClick={onClear}
          disabled={logs.length === 0}
        >
          Clear
        </Button>
      </div>
      <div className={styles.logList}>
        {logs.length === 0 && (
          <div className={styles.empty}>
            <Body1>No API calls yet</Body1>
          </div>
        )}
        {logs.map((entry) => (
          <div key={entry.id} className={styles.logEntry}>
            <div className={styles.logHeader}>
              <span
                className={styles.logMethod}
                style={{ color: methodColors[entry.method] || tokens.colorNeutralForeground1 }}
              >
                {entry.method}
              </span>
              <span className={styles.logUrl}>{entry.url}</span>
            </div>
            <div className={styles.logMeta}>
              <Badge
                appearance="filled"
                color={getStatusColor(entry.responseStatus)}
                size="small"
              >
                {entry.responseStatus}
              </Badge>
              <Caption1>{entry.duration}ms</Caption1>
              <Caption1>
                {entry.timestamp.toLocaleTimeString()}
              </Caption1>
            </div>
            {entry.requestBody !== undefined && entry.requestBody !== null && (
              <div className={styles.logBody}>
                <Caption1 style={{ fontWeight: 600 }}>Request:</Caption1>
                {'\n'}
                {JSON.stringify(entry.requestBody, null, 2)}
              </div>
            )}
            {entry.responseBody !== undefined && entry.responseBody !== null && (
              <div className={styles.logBody}>
                <Caption1 style={{ fontWeight: 600 }}>Response:</Caption1>
                {'\n'}
                {JSON.stringify(entry.responseBody, null, 2)}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
