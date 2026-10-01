import request from './request'

export function login(data) {
  return request.post('/auth/login', data)
}

export function getUserList(params) {
  return request.get('/users', { params })
}
