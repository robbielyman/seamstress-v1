seamstress.event.addSubscriber({ 'midi' }, function(event)
  seamstress.clock.midi(event[2])
  return true
end, { priority = 0 })

return { nil, true }
