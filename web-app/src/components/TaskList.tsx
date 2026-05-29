import { useState } from 'react';
import {
  makeStyles,
  tokens,
  Card,
  CardHeader,
  Body1,
  Caption1,
  Badge,
  Button,
  Menu,
  MenuTrigger,
  MenuList,
  MenuItem,
  MenuPopover,
  Spinner,
} from '@fluentui/react-components';
import {
  MoreHorizontal24Regular,
  Delete24Regular,
  ArrowClockwise24Regular,
} from '@fluentui/react-icons';
import { TodoTask, TodoStatus } from '../types';
import { tasksApi } from '../api/tasksApi';

const useStyles = makeStyles({
  container: {
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '12px',
  },
  card: {
    padding: '12px 16px',
  },
  cardContent: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  taskInfo: {
    display: 'flex',
    flexDirection: 'column',
    gap: '4px',
    flex: 1,
  },
  taskMeta: {
    display: 'flex',
    gap: '12px',
    alignItems: 'center',
  },
  actions: {
    display: 'flex',
    gap: '4px',
    alignItems: 'center',
  },
  empty: {
    textAlign: 'center' as const,
    padding: '40px',
    color: tokens.colorNeutralForeground3,
  },
});

const statusColors: Record<TodoStatus, 'informative' | 'success' | 'warning' | 'danger'> = {
  Open: 'informative',
  InProgress: 'warning',
  Done: 'success',
  Cancelled: 'danger',
};

const statusLabels: Record<TodoStatus, string> = {
  Open: 'Open',
  InProgress: 'In Progress',
  Done: 'Done',
  Cancelled: 'Cancelled',
};

interface TaskListProps {
  tasks: TodoTask[];
  loading: boolean;
  onRefresh: () => void;
}

export function TaskList({ tasks, loading, onRefresh }: TaskListProps) {
  const styles = useStyles();

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <Body1 style={{ fontWeight: 600 }}>
          Tasks ({tasks.length})
        </Body1>
        <Button
          appearance="subtle"
          icon={<ArrowClockwise24Regular />}
          onClick={onRefresh}
          disabled={loading}
        >
          Refresh
        </Button>
      </div>
      {loading && <Spinner size="medium" label="Loading tasks..." />}
      {!loading && tasks.length === 0 && (
        <div className={styles.empty}>
          <Body1>No tasks yet. Create one above!</Body1>
        </div>
      )}
      {tasks.map((task) => (
        <TaskCard key={task.id} task={task} onChanged={onRefresh} />
      ))}
    </div>
  );
}

interface TaskCardProps {
  task: TodoTask;
  onChanged: () => void;
}

function TaskCard({ task, onChanged }: TaskCardProps) {
  const styles = useStyles();
  const [updating, setUpdating] = useState(false);

  const handleStatusChange = async (status: TodoStatus) => {
    setUpdating(true);
    try {
      await tasksApi.update(task.id, { status });
      onChanged();
    } catch {
      // shown in console
    } finally {
      setUpdating(false);
    }
  };

  const handleDelete = async () => {
    setUpdating(true);
    try {
      await tasksApi.delete(task.id);
      onChanged();
    } catch {
      // shown in console
    } finally {
      setUpdating(false);
    }
  };

  return (
    <Card className={styles.card}>
      <CardHeader
        header={
          <div className={styles.cardContent}>
            <div className={styles.taskInfo}>
              <Body1 style={{ fontWeight: 600 }}>{task.title}</Body1>
              {task.description && <Caption1>{task.description}</Caption1>}
              <div className={styles.taskMeta}>
                <Badge
                  appearance="filled"
                  color={statusColors[task.status]}
                  size="small"
                >
                  {statusLabels[task.status]}
                </Badge>
                {task.dueDate && (
                  <Caption1>
                    Due: {new Date(task.dueDate).toLocaleDateString()}
                  </Caption1>
                )}
              </div>
            </div>
            <div className={styles.actions}>
              <Menu>
                <MenuTrigger disableButtonEnhancement>
                  <Button
                    appearance="subtle"
                    icon={<MoreHorizontal24Regular />}
                    disabled={updating}
                    size="small"
                  />
                </MenuTrigger>
                <MenuPopover>
                  <MenuList>
                    <MenuItem onClick={() => handleStatusChange('Open')}>
                      Set Open
                    </MenuItem>
                    <MenuItem onClick={() => handleStatusChange('InProgress')}>
                      Set In Progress
                    </MenuItem>
                    <MenuItem onClick={() => handleStatusChange('Done')}>
                      Set Done
                    </MenuItem>
                    <MenuItem onClick={() => handleStatusChange('Cancelled')}>
                      Set Cancelled
                    </MenuItem>
                  </MenuList>
                </MenuPopover>
              </Menu>
              <Button
                appearance="subtle"
                icon={<Delete24Regular />}
                onClick={handleDelete}
                disabled={updating}
                size="small"
              />
            </div>
          </div>
        }
      />
    </Card>
  );
}
