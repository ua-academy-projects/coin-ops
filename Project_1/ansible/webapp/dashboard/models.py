from django.db import models


class ExchangeRate(models.Model):
    id = models.BigAutoField(primary_key=True)
    r030 = models.IntegerField()
    txt = models.TextField()
    rate = models.DecimalField(max_digits=18, decimal_places=6)
    cc = models.CharField(max_length=16)
    exchange_date = models.DateField()
    collected_at = models.DateTimeField()
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "exchange_rates"
        ordering = ["cc"]
