import request from './request'

export function login(data) {
  return request.post('/admin/login', data)
}

export function totpSetup() {
  return request.post('/admin/totp/setup')
}

export function totpConfirm(code) {
  return request.post('/admin/totp/confirm', { code })
}

export function changeAdminPassword(data) {
  return request.post('/admin/password', data)
}

export function getUserList(params) {
  return request.get('/users', { params })
}
