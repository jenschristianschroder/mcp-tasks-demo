import { useState } from 'react';
import {
  makeStyles,
  Input,
  Textarea,
  Button,
  Field,
  Card,
  CardHeader,
  Title3,
} from '@fluentui/react-components';
import { Add24Regular } from '@fluentui/react-icons';
import { tasksApi } from '../api/tasksApi';

const useStyles = makeStyles({
  card: {
    padding: '16px',
  },
  form: {
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
  },
  row: {
    display: 'flex',
    gap: '12px',
    alignItems: 'flex-end',
  },
});

interface TaskFormProps {
  onCreated: () => void;
}

export function TaskForm({ onCreated }: TaskFormProps) {
  const styles = useStyles();
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;

    setSubmitting(true);
    try {
      await tasksApi.create({
        title: title.trim(),
        description: description.trim() || null,
        dueDate: dueDate ? new Date(dueDate).toISOString() : null,
      });
      setTitle('');
      setDescription('');
      setDueDate('');
      onCreated();
    } catch {
      // error shown in console
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Card className={styles.card}>
      <CardHeader header={<Title3>Create Task</Title3>} />
      <form onSubmit={handleSubmit} className={styles.form}>
        <div className={styles.row}>
          <Field label="Title" required style={{ flex: 1 }}>
            <Input
              value={title}
              onChange={(_, d) => setTitle(d.value)}
              placeholder="What needs to be done?"
            />
          </Field>
          <Field label="Due Date">
            <Input
              type="date"
              value={dueDate}
              onChange={(_, d) => setDueDate(d.value)}
            />
          </Field>
        </div>
        <Field label="Description">
          <Textarea
            value={description}
            onChange={(_, d) => setDescription(d.value)}
            placeholder="Optional details..."
            resize="vertical"
          />
        </Field>
        <Button
          appearance="primary"
          type="submit"
          icon={<Add24Regular />}
          disabled={!title.trim() || submitting}
        >
          {submitting ? 'Creating...' : 'Create Task'}
        </Button>
      </form>
    </Card>
  );
}
