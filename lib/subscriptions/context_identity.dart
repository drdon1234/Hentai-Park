/// 账号身份参与基线摘要，会话续期、重试计数与展示名称不应重置已见索引。
Object? subscriptionAccountIdentity(Object? value) {
  if (value is Map) {
    const transient = {
      'token',
      'accesstoken',
      'refreshtoken',
      'expires',
      'expiresat',
      'expiry',
      'retryat',
      'failures',
      'ratelimited',
      'name',
      'updatedat',
    };
    final keys = value.keys.map((e) => e.toString()).toList()..sort();
    return {
      for (final key in keys)
        if (!transient.contains(key.toLowerCase().replaceAll('_', '')))
          key: subscriptionAccountIdentity(value[key]),
    };
  }
  if (value is List) return value.map(subscriptionAccountIdentity).toList();
  return value;
}
