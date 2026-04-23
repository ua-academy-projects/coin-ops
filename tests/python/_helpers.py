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
