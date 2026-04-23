def description_from_names(*names: str):
    return [(name, None, None, None, None, None, None) for name in names]


class CursorSpy:
    def __init__(self, rows=None, description=None):
        self.rows = rows or []
        self.description = description or []
        self.executed = []

    def execute(self, sql, params=None):
        self.executed.append((sql, params))

    def fetchall(self):
        return list(self.rows)

    def fetchone(self):
        if not self.rows:
            return None
        return self.rows[0]

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


class ConnectionSpy:
    def __init__(self, rows=None, description=None):
        self.cursor_obj = CursorSpy(rows=rows, description=description)
        self.closed = False
        self.rollback_calls = 0
        self.commit_calls = 0

    def cursor(self):
        return self.cursor_obj

    def close(self):
        self.closed = True

    def rollback(self):
        self.rollback_calls += 1

    def commit(self):
        self.commit_calls += 1


class ChannelSpy:
    def __init__(self):
        self.acks = []
        self.nacks = []
        self.published = []

    def basic_ack(self, delivery_tag):
        self.acks.append(delivery_tag)

    def basic_nack(self, delivery_tag, requeue):
        self.nacks.append((delivery_tag, requeue))

    def basic_publish(self, *args, **kwargs):
        self.published.append((args, kwargs))
