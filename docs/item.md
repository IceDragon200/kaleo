# Kaleo Calendar Items

Kaleo allows defining calendar items, these are typically single events or spans.

```kdl
item {
  starts_at {
    date "2024-07-19"
    // `time` is optional, if only the date is supplied, then the event is expected to be all day
    time "13:00:00"
    // `timezone` is optional, by default it will be UTC
    timezone "EST"
  }
  // Optional
  ends_at {
    date "2024-07-19"
    time "14:00:00"
    timezone "EST"
  }
  // You can ask to be reminded of an item by setting the remind_me
  remind_me {
    // Like with the item itself, you can specific a starting date when reminders should begin
    // this should be used with the `every` key
    starts_at {
      date "2024-07-18"
      time "19:00:00"
    }
    every {
      hours 1
    }
  }
  name "Anything you'd like to name this item"
  notes "Any additional notes about this calendar item"
  metadata {
    // metadata can contain anything
  }
  modules {
    // module specific configurations
  }
}
```
