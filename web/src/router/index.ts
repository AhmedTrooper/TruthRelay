import { createRouter, createWebHistory } from 'vue-router';

const routes = [
  { path: '/', name: 'dashboard', component: () => import('../features/dashboard/views/DashboardView.vue') },
  { path: '/bulletins', name: 'bulletins', component: () => import('../features/bulletins/views/BulletinsView.vue') },
  { path: '/requests', name: 'requests', component: () => import('../features/requests/views/RequestsView.vue') },
  { path: '/moderators', name: 'moderators', component: () => import('../features/moderators/views/ModeratorsView.vue') },
  { path: '/sync', name: 'sync', component: () => import('../features/sync/views/SyncView.vue') },
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
});