use reinhardt::db::orm::{CustomManager, Model};
use reinhardt::di::{Depends, InjectableKey, KeyedDepends, KeyedFactoryOutput};
use reinhardt::rest::serializers::ModelSerializer;

pub fn dependency_access<'a, K: InjectableKey, T: Send + Sync + 'static>(
    keyed: &'a KeyedDepends<K, T>,
    self_keyed: &'a Depends<T>,
) -> (&'a T, &'a T) {
    (keyed, self_keyed)
}

pub fn explicit_provider<K: InjectableKey, T: Send + Sync + 'static>(
    value: T,
) -> KeyedFactoryOutput<K, T> {
    KeyedFactoryOutput::new(value)
}

pub fn serializer<M: Model>() -> ModelSerializer<M> {
    ModelSerializer::new()
}

pub async fn crud<M: Model>(model: &M, id: M::PrimaryKey) -> reinhardt::Result<()> {
    let manager = M::objects();
    let _found = manager.get(id.clone()).first().await?;
    let _created = manager.create(model).await?;
    let _updated = manager.update(model).await?;
    let _page = manager.paginate(1, 20).all().await?;
    manager.delete(id).await?;
    Ok(())
}

pub fn backend_contract<B: reinhardt::auth::AuthBackend>() {}
pub fn rest_contract<A: reinhardt::auth::RestAuthentication>() {}
