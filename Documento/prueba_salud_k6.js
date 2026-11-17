import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
    vus: 5,
    duration: '15s',
};

export default function () {
    const respuesta = http.get(
        'http://host.docker.internal:3000/api/health'
    );

    check(respuesta, {
        'Respuesta HTTP 200': (r) => r.status === 200,
    });

    sleep(1);
}
