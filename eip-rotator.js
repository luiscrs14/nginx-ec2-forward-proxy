const aws = require("aws-sdk");

const TagRotate = "rotate";
const TagOne = "1";

exports.handler = async () => {
  const ec2 = new aws.EC2({region: 'eu-west-1'});

  const addTag = (resourceId, tag, value) =>
    ec2
      .createTags({
        Resources: [resourceId],
        Tags: [{ Key: tag, Value: value }],
      })
      .promise();

  const getAddresses = async () =>
    (await ec2.describeAddresses().promise()).Addresses;

  let addresses = await getAddresses();
  if (!addresses) {
    console.error("describeAddresses API did not provide an address list");
    return;
  }

  const addressesToRotate = addresses.filter(
    (_) =>
      !!_.AssociationId &&
      !!_.InstanceId &&
      !!_.PrivateIpAddress &&
      _.Tags?.find((_) => _.Key === TagRotate && _.Value === TagOne)
  );
  if (!addressesToRotate.length) {
    console.warn(
      "Could not find any IPs with tag rotate=1 that are attached to an EC2 instance"
    );
  }

  for (const addressToRotate of addressesToRotate) {
    const instanceId = addressToRotate.InstanceId;
    const previousPublicIp = addressToRotate.PublicIp;
    const privateIp = addressToRotate.PrivateIpAddress;
    const previousAssociation = addressToRotate.AssociationId;
    const previousAllocation = addressToRotate.AllocationId;
    console.log(instanceId, `Current IP: ${previousPublicIp} -> ${privateIp}`);
    console.log(instanceId, `Association ID: ${previousAssociation}`);
    console.log(instanceId, `Allocation ID: ${previousAllocation}`);
    try {
      const allocationResult = await ec2.allocateAddress().promise();
      const newAllocationId = allocationResult.AllocationId;
      if (!newAllocationId) {
        console.error(instanceId, "Failed to allocate new public IP");
      } else {
        await addTag(newAllocationId, TagRotate, TagOne);
        console.log(
          instanceId,
          `Associating: ${allocationResult.PublicIp} -> ${privateIp}`
        );
        await ec2
          .associateAddress({
            AllocationId: newAllocationId,
            AllowReassociation: true,
            InstanceId: instanceId,
            PrivateIpAddress: privateIp,
          })
          .promise();
      }
    } catch (e) {
      console.error(instanceId, "Unexpected error", e.message);
    }
    
    try {
      console.log(
        `Releasing unused public IP: ${previousPublicIp} (${previousAllocation})`
      );
      await ec2
        .releaseAddress({ AllocationId: previousAllocation })
        .promise();
    } catch (e) {
      console.error(
        `Could not release unused address ${previousPublicIp} (${previousAllocation}): ${e.message}`
      );
    }
  }

  addresses = await getAddresses();
  if (!addresses) {
    console.warn("Skipping cleanup");
    return;
  }
};
