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
  Input,
  Textarea,
  Field,
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
  Edit24Regular,
  Checkmark24Regular,
  Dismiss24Regular,
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
  editForm: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '8px',
    width: '100%',
  },
  editRow: {
    display: 'flex',
    gap: '8px',
    alignItems: 'flex-end',
  },
  editActions: {
    display: 'flex',
    gap: '4px',
    marginTop: '4px',
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
  const [editing, setEditing] = useState(false);
  const [editTitle, setEditTitle] = useState(task.title);
  const [editDescription, setEditDescription] = useState(task.description || '');
  const [editDueDate, setEditDueDate] = useState(
    task.dueDate ? new Date(task.dueDate).toISOString().split('T')[0] : ''
  );

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

  const handleEdit = () => {
    setEditTitle(task.title);
    setEditDescription(task.description || '');
    setEditDueDate(
      task.dueDate ? new Date(task.dueDate).toISOString().split('T')[0] : ''
    );
    setEditing(true);
  };

  const handleCancelEdit = () => {
    setEditing(false);
  };

  const handleSaveEdit = async () => {
    setUpdating(true);
    try {
      await tasksApi.update(task.id, {
        title: editTitle.trim(),
        description: editDescription.trim() || null,
        dueDate: editDueDate ? new Date(editDueDate).toISOString() : null,
      });
      setEditing(false);
      onChanged();
    } catch {
      // shown in console
    } finally {
      setUpdating(false);
    }
  };

  if (editing) {
    return (
      <Card className={styles.card}>
        <div className={styles.editForm}>
          <div className={styles.editRow}>
            <Field label="Title" required style={{ flex: 1 }}>
              <Input
                value={editTitle}
                onChange={(_, d) => setEditTitle(d.value)}
              />
            </Field>
            <Field label="Due Date">
              <Input
                type="date"
                value={editDueDate}
                onChange={(_, d) => setEditDueDate(d.value)}
              />
            </Field>
          </div>
          <Field label="Description">
            <Textarea
              value={editDescription}
              onChange={(_, d) => setEditDescription(d.value)}
              resize="vertical"
            />
          </Field>
          <div className={styles.editActions}>
            <Button
              appearance="primary"
              icon={<Checkmark24Regular />}
              onClick={handleSaveEdit}
              disabled={!editTitle.trim() || updating}
              size="small"
            >
              {updating ? 'Saving...' : 'Save'}
            </Button>
            <Button
              appearance="subtle"
              icon={<Dismiss24Regular />}
              onClick={handleCancelEdit}
              disabled={updating}
              size="small"
            >
              Cancel
            </Button>
          </div>
        </div>
      </Card>
    );
  }

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
              <Button
                appearance="subtle"
                icon={<Edit24Regular />}
                onClick={handleEdit}
                disabled={updating}
                size="small"
              />
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
